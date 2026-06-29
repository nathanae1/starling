import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/identity_provider.dart';
import '../providers/media_provider.dart';
import '../providers/service_providers.dart';
import '../providers/sync_provider.dart';
import '../services/crypto/feed_key_ratchet.dart';
import '../services/media_service.dart';
import '../sync/key_refresh_throttle.dart';
import '../utils/debug_log.dart';

/// Resolve and decrypt the media blob [hash] authored by [pubkey].
///
/// Walks the candidate feed-key chain roots (own identity key + retired
/// history, or the follow's key + archived roots), tries a local decrypt,
/// fetches the encrypted blob from the peer if it's not on disk, and — if
/// the cached key is stale — pulls a throttled one-shot key-refresh sync and
/// retries. Returns the plaintext, or null if it can't be produced.
///
/// On success the follow's decrypt-failure flag is cleared; on terminal
/// failure it's stamped (driving the "Key — stale" status tile). [mounted]
/// lets a widget caller bail out of the post-sync retry after disposal.
///
/// Shared by [EncryptedImage] (post media) and [EncryptedAvatar] (profile
/// photos) so both use the identical rotation-aware decrypt pipeline.
Future<Uint8List?> resolveAndDecryptMedia(
  WidgetRef ref, {
  required String hash,
  required String pubkey,
  required int? msgSeq,
  bool Function()? mounted,
}) async {
  final candidates = await _candidateFeedKeys(ref, pubkey);
  if (candidates.isEmpty) return null;
  final mediaService = ref.read(mediaServiceProvider);

  final local = await _tryDecryptWithAny(
    ref,
    mediaService,
    candidates,
    hash: hash,
    pubkey: pubkey,
    msgSeq: msgSeq,
  );
  if (local != null) {
    await _clearDecryptFailure(ref, pubkey);
    return local;
  }

  // Try fetching the encrypted blob. RemoteMediaFetcher returns null both
  // for "already cached on disk" and "no peer reachable" — we can't tell
  // which, so we decrypt again unconditionally below.
  final fetcher = ref.read(remoteMediaFetcherProvider);
  await fetcher.fetch(hash, pubkey);
  final afterFetch = await _tryDecryptWithAny(
    ref,
    mediaService,
    candidates,
    hash: hash,
    pubkey: pubkey,
    msgSeq: msgSeq,
  );
  if (afterFetch != null) {
    await _clearDecryptFailure(ref, pubkey);
    return afterFetch;
  }

  // Two decrypt attempts under the cached key failed — either the blob was
  // cached under a different epoch, or the peer rotated and the rotation
  // hasn't reached us. Pull a throttled one-shot sync (which inlines any
  // pending rotation via the manifest) and retry once.
  final refreshed = await _refreshKeyAndRetry(
    ref,
    mediaService,
    hash: hash,
    pubkey: pubkey,
    msgSeq: msgSeq,
    mounted: mounted,
  );
  if (refreshed != null) {
    await _clearDecryptFailure(ref, pubkey);
  }
  return refreshed;
}

Future<Uint8List?> _refreshKeyAndRetry(
  WidgetRef ref,
  MediaService mediaService, {
  required String hash,
  required String pubkey,
  required int? msgSeq,
  bool Function()? mounted,
}) async {
  final throttle = ref.read(keyRefreshThrottleProvider);
  final clock = ref.read(clockProvider);
  if (!throttle.tryAcquire(pubkey)) {
    // Already attempted recently — record the staleness signal and give up
    // for this round; the cooldown will lapse in due course.
    await _recordDecryptFailure(ref, pubkey, clock.nowUnixSeconds());
    return null;
  }
  debugLog(
    'media_decrypt',
    'media decrypt failed for $pubkey; refreshing feed key',
  );
  try {
    await ref.read(syncEngineProvider).syncOnePeerByPubkey(pubkey);
  } catch (e) {
    debugLog('media_decrypt', 'feed-key refresh sync failed for $pubkey: $e');
  }
  if (mounted != null && !mounted()) return null;
  final refreshed = await _candidateFeedKeys(ref, pubkey);
  if (refreshed.isEmpty) return null;
  final retry = await _tryDecryptWithAny(
    ref,
    mediaService,
    refreshed,
    hash: hash,
    pubkey: pubkey,
    msgSeq: msgSeq,
  );
  if (retry != null) return retry;
  await _recordDecryptFailure(ref, pubkey, clock.nowUnixSeconds());
  return null;
}

Future<void> _recordDecryptFailure(
  WidgetRef ref,
  String pubkey,
  int now,
) async {
  // Stamp the staleness signal on the follow row so connection settings can
  // show "Key — stale". Skip for own-pubkey: a self-decrypt mismatch is a
  // different bug class and we never look up our own row that way.
  final identity = await ref.read(identityControllerProvider.future);
  if (identity != null && identity.pubkey == pubkey) return;
  final storage = ref.read(storageServiceProvider);
  await storage.setLastDecryptFailureAt(pubkey, now);
}

Future<void> _clearDecryptFailure(WidgetRef ref, String pubkey) async {
  final identity = await ref.read(identityControllerProvider.future);
  if (identity != null && identity.pubkey == pubkey) return;
  final storage = ref.read(storageServiceProvider);
  await storage.clearLastDecryptFailureIfSet(pubkey);
}

/// Walks [chainRoots] in priority order, derives the per-message AEAD key
/// from each (using [msgSeq]), and tries to decrypt. Returns the first
/// plaintext that comes through, or null if everything failed.
Future<Uint8List?> _tryDecryptWithAny(
  WidgetRef ref,
  MediaService mediaService,
  List<Uint8List> chainRoots, {
  required String hash,
  required String pubkey,
  required int? msgSeq,
}) async {
  if (msgSeq == null) {
    // Legacy / pre-v9 row with no msg_seq stored — no way to derive the key.
    debugLog('media_decrypt', 'no msgSeq for media $hash (pubkey=$pubkey)');
    return null;
  }
  final crypto = ref.read(cryptoServiceProvider);
  for (final root in chainRoots) {
    final msgKey = deriveMsgKey(root, msgSeq, crypto);
    try {
      final bytes = await mediaService.readPlaintext(hash, msgKey);
      if (bytes != null) return bytes;
    } catch (_) {
      // Wrong key — try the next chain root.
      continue;
    }
  }
  debugLog(
    'media_decrypt',
    'no candidate key decrypted media $hash '
        '(pubkey=$pubkey, msgSeq=$msgSeq, tried=${chainRoots.length})',
  );
  return null;
}

/// Returns the chain roots to try when decrypting media for [pubkey], in
/// priority order. Own content: current identity feed key first, then
/// retired keys. Followee content: current `Follow.feedKey` first, then
/// archived chain roots from `follow_feed_key_history`.
Future<List<Uint8List>> _candidateFeedKeys(WidgetRef ref, String pubkey) async {
  final identity = await ref.read(identityControllerProvider.future);
  final storage = ref.read(storageServiceProvider);
  if (identity != null && identity.pubkey == pubkey) {
    final history = await storage.getFeedKeyHistory();
    // Newest retired first — recent posts dominate, minimising wasted tries.
    history.sort((a, b) => b.validUntil.compareTo(a.validUntil));
    return [identity.feedKey, ...history.map((r) => r.feedKey)];
  }
  final follow = await storage.getFollow(pubkey);
  if (follow == null) return const [];
  final history = await storage.getFollowFeedKeyHistory(pubkey);
  history.sort((a, b) => b.validUntil.compareTo(a.validUntil));
  return [follow.feedKey, ...history.map((r) => r.feedKey)];
}
