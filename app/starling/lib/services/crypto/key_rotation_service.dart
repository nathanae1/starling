import 'dart:typed_data';

import '../../sync/sealed_delivery.dart';
import '../clock.dart';
import '../crypto_service.dart';
import '../storage_service.dart';
import 'key_cache.dart';
import 'publish_lock.dart';

/// Generates a new feed key and distributes it to remaining followers when
/// a follower is removed (Plan 13).
///
/// Steps for `rotate(removedPubkey: X)`:
///   1. Append the current key to `feed_key_history` with the half-open
///      window `[identity.feedKeyValidFrom, now)`.
///   2. Generate a fresh 256-bit key, set it as `identity.feedKey` with
///      `feedKeyEpoch = 0` and `feedKeyValidFrom = now`. Update the
///      [FeedKeyCache] entry for our own pubkey.
///   3. For each remaining accepted inbound follower (excluding X): seal
///      the new feed key per follower (`sync/sealed_delivery.dart`) into
///      `pending_key_distributions`.
///   4. Defensively clear any pending distributions that still target X.
///
/// The whole rotation runs under a [PublishLock] shared with the publish
/// path so a post in flight can't observe a torn state. Concurrent
/// `rotate()` calls serialize.
class KeyRotationService {
  KeyRotationService({
    required CryptoService crypto,
    required StorageService storage,
    required Clock clock,
    required FeedKeyCache feedKeyCache,
    required PublishLock publishLock,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
  })  : _crypto = crypto,
        _storage = storage,
        _clock = clock,
        _feedKeyCache = feedKeyCache,
        _publishLock = publishLock,
        _ownSecretKeyLookup = ownSecretKeyLookup;

  final CryptoService _crypto;
  final StorageService _storage;
  final Clock _clock;
  final FeedKeyCache _feedKeyCache;
  final PublishLock _publishLock;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;

  Future<void> rotate({required String removedPubkey}) {
    return _publishLock.synchronized(() => _rotateLocked(removedPubkey));
  }

  Future<void> _rotateLocked(String removedPubkey) async {
    final identity = await _storage.getIdentity();
    if (identity == null) {
      throw StateError('cannot rotate feed key: no identity loaded');
    }
    final secretKey = await _ownSecretKeyLookup();
    if (secretKey == null) {
      throw StateError('cannot rotate feed key: no secret key available');
    }

    final now = _clock.nowUnixSeconds();

    // 1. Retire the current key.
    await _storage.appendFeedKeyHistory(
      feedKey: identity.feedKey,
      feedKeyEpoch: identity.feedKeyEpoch,
      validFrom: identity.feedKeyValidFrom == 0
          ? identity.createdAt
          : identity.feedKeyValidFrom,
      validUntil: now,
    );

    // 2. Generate the new key and persist + cache it. Reset the per-
    //    message sequence counter — fresh chain root means msg_seq
    //    restarts at 0 under the new key.
    final newKey = _crypto.randomBytes(32);
    final newIdentity = identity.copyWith(
      feedKey: newKey,
      feedKeyEpoch: 0,
      feedKeyValidFrom: now,
      msgSeqCounter: 0,
    );
    await _storage.saveIdentity(newIdentity);
    _feedKeyCache.put(identity.pubkey, newKey, 0);

    // 3. Seal and queue for each remaining follower.
    await sealAndQueueForAcceptedFollowers(
      crypto: _crypto,
      storage: _storage,
      channel: feedKeyChannel,
      identity: identity,
      secretKey: secretKey,
      plaintext: newKey,
      createdAt: now,
      exclude: {removedPubkey},
    );

    // 4. Sweep stragglers for the removed pubkey.
    await _storage.clearPendingDistributionsFor(removedPubkey);
  }
}
