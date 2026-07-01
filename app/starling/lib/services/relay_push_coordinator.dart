import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'relay_push_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Cap one `POST /events` batch: whichever of these trips first closes the
/// chunk. ~100 text posts ≈ 200 KB stays far under the relay's 4 MiB body
/// limit and keeps a single Tor request inside the 30s timeout; a mid-
/// backfill failure re-sends at most one chunk (inserts are idempotent).
const int kPushBatchMaxItems = 100;
const int kPushBatchMaxBytes = 1 << 20; // 1 MiB

/// Runaway guard for manifest paging (50 pages × 1000 = 50k events). On
/// hitting the cap the partial id set stands — worst case some present
/// events are re-pushed, which the relay dedups.
const int kMaxManifestPages = 50;

/// Owner-side push of content to the paired Relay (Plan 15), using the
/// "best-effort + reconcile" model:
///
/// - [backfill] runs once at pair time: pushes the Owner's full own-event
///   history + media.
/// - [pushPublished] fires after each new post: a single best-effort push.
/// - [reconcile] self-heals: diffs local own-event ids AND media hashes
///   against the Relay's `/manifest` + `/media-manifest` (both paged to
///   completion) and re-pushes anything missing. Safe to call often — the
///   Relay's `POST /events` / `POST /media` are idempotent.
///
/// `relayBackfillComplete` is flipped by EITHER pass once events and media
/// have both converged, so a backfill stranded by one transport error
/// (D2) heals on the next reconcile instead of showing "syncing…" forever.
///
/// All methods no-op when no Relay is paired, and swallow/log transport
/// errors (the next reconcile retries). They never throw into callers.
class RelayPushCoordinator {
  RelayPushCoordinator({
    required RelayPushService pushService,
    required StorageService storage,
    required http.Client relayClient,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required Future<Uint8List?> Function(String hash) mediaBytesLookup,
    Duration timeout = const Duration(seconds: 30),
  }) : _push = pushService,
       _storage = storage,
       _client = relayClient,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _mediaBytesLookup = mediaBytesLookup,
       _timeout = timeout;

  final RelayPushService _push;
  final StorageService _storage;
  final http.Client _client;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final Future<Uint8List?> Function(String hash) _mediaBytesLookup;
  final Duration _timeout;

  /// Push a freshly-published event (+ its media) to the paired Relay.
  Future<void> pushPublished(Event signed, Uint8List encryptedBytes) async {
    await _withRelay((ctx) async {
      await _push.pushEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        items: [
          RelayPushItem(
            id: signed.id,
            encryptedEvent: EncryptedEvent.fromBytes(encryptedBytes),
          ),
        ],
      );
      final failures = await _pushMediaHashes({
        for (final m in signed.media) m.hash,
      }, ctx);
      developer.log(
        'relay push published ${signed.id} media=${signed.media.length} '
        'mediaFailures=$failures',
        name: 'relay_push',
      );
    });
  }

  /// One-shot at pair time: the relay manifest is empty, so the diff IS
  /// the full history push.
  Future<void> backfill() => _reconcileAndMark('backfill');

  /// Self-heal: push any own events / media blobs the Relay doesn't hold.
  Future<void> reconcile() => _reconcileAndMark('reconcile');

  // --- internals ---

  Future<void> _reconcileAndMark(String what) async {
    await _withRelay((ctx) async {
      final converged = await _syncToRelay(ctx);
      if (converged && !ctx.backfillComplete) {
        await _storage.markRelayBackfillComplete(ctx.relayId);
        developer.log('relay $what complete', name: 'relay_push');
      }
    });
  }

  /// Diff the relay's events + media against local state and push what's
  /// missing. Returns true when the relay verifiably holds everything we
  /// can give it (events pushed, media diffed, zero push failures). Event
  /// push errors propagate to [_withRelay]; media errors are per-blob.
  Future<bool> _syncToRelay(_RelayCtx ctx) async {
    final present = await _relayEventIds(ctx.baseUrl);
    if (present == null) return false; // relay unreachable — next tick

    // Diff ids first; encrypted payloads are loaded only for the missing
    // ids (the common nothing-missing pass reads no payload bytes at all).
    final events = await _storage.getEvents(pubkey: ctx.pubkey);
    final missingItems = <RelayPushItem>[];
    for (final e in events) {
      // Chatroom kinds (100-103) are membership-scoped — never hand them to
      // the relay, which re-serves the owner's feed to followers (Plan 17).
      if (e.kind.isRoomScoped) continue;
      if (present.contains(e.id)) continue;
      // Own events authored before schema v2 have no stored wire payload
      // and are skipped (the Relay can't serve what we can't hand it
      // verbatim).
      final payload = await _storage.getEncryptedPayload(e.id);
      if (payload == null) continue;
      missingItems.add(
        RelayPushItem(
          id: e.id,
          encryptedEvent: EncryptedEvent.fromBytes(payload),
        ),
      );
    }
    if (missingItems.isNotEmpty) {
      await _pushEventsChunked(missingItems, ctx);
      developer.log(
        'relay sync pushed ${missingItems.length} missing events',
        name: 'relay_push',
      );
    }

    // D8: diff media presence too. Expected = every hash referenced by an
    // own event (payload-less pre-v2 events included — pushing their media
    // is harmless); blobs no longer on disk are skipped below.
    final relayHashes = await _relayMediaHashes(ctx);
    if (relayHashes == null) return false; // retry next tick
    final expected = <String>{
      for (final e in events)
        for (final m in e.media)
          if (m.hash.isNotEmpty) m.hash,
    };
    final failures = await _pushMediaHashes(
      expected.difference(relayHashes),
      ctx,
    );
    return failures == 0;
  }

  /// Push [items] as bounded batches — one signed POST each. Throws on the
  /// first failed batch (already-sent chunks are idempotent on re-push).
  Future<void> _pushEventsChunked(
    List<RelayPushItem> items,
    _RelayCtx ctx,
  ) async {
    var start = 0;
    while (start < items.length) {
      var end = start;
      var bytes = 0;
      while (end < items.length && end - start < kPushBatchMaxItems) {
        final itemBytes = items[end].encryptedEvent.payload.length;
        // An item that would overshoot closes the chunk — unless it's the
        // chunk's first item (an oversized single event ships alone).
        if (end > start && bytes + itemBytes > kPushBatchMaxBytes) break;
        bytes += itemBytes;
        end++;
      }
      await _push.pushEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        items: items.sublist(start, end),
      );
      start = end;
    }
  }

  /// Push the blobs for [hashes], tolerating per-blob failures (one bad
  /// upload must not strand the rest, D8). Returns the failure count.
  /// Hashes with no bytes on disk are skipped — they can never heal, so
  /// they don't count against convergence.
  Future<int> _pushMediaHashes(Set<String> hashes, _RelayCtx ctx) async {
    var failures = 0;
    for (final hash in hashes) {
      if (hash.isEmpty) continue;
      final blob = await _mediaBytesLookup(hash);
      if (blob == null) continue;
      try {
        await _push.pushMedia(
          relayBaseUrl: ctx.baseUrl,
          ownerPubkeyBytes: ctx.pubkeyBytes,
          ownerSecretKey: ctx.secretKey,
          hash: hash,
          blob: blob,
        );
      } catch (e) {
        failures++;
        developer.log('media push failed for $hash: $e', name: 'relay_push');
      }
    }
    return failures;
  }

  /// Resolves the paired relay + identity + secret key into a [_RelayCtx]
  /// and runs [body]. No-ops (logs) when anything required is missing or
  /// the body throws — callers never see an exception.
  Future<void> _withRelay(Future<void> Function(_RelayCtx ctx) body) async {
    try {
      final relay = await _storage.getPairedRelay();
      if (relay == null) return;
      final identity = await _identityLookup();
      final secretKey = await _ownSecretKeyLookup();
      if (identity == null || secretKey == null) return;
      await body(
        _RelayCtx(
          relayId: relay.relayId,
          baseUrl: httpBaseUrlForAddress(relay.relayOnion),
          pubkey: identity.pubkey,
          pubkeyBytes: decodeStoredPubkey(identity.pubkey),
          secretKey: secretKey,
          backfillComplete: relay.backfillComplete,
        ),
      );
    } catch (e) {
      developer.log('relay push skipped: $e', name: 'relay_push');
    }
  }

  /// All event ids the Relay holds, paging `/manifest` to completion via
  /// the `until`/`until_id` keyset cursor. Null if the Relay is
  /// unreachable or answers garbage.
  Future<Set<String>?> _relayEventIds(String baseUrl) async {
    final ids = <String>{};
    int? until;
    String? untilId;
    for (var page = 0; page < kMaxManifestPages; page++) {
      final query = <String, String>{
        if (until != null) 'until': until.toString(),
        if (until != null && untilId != null) 'until_id': untilId,
      };
      final uri = Uri.parse(
        '$baseUrl/manifest',
      ).replace(queryParameters: query.isEmpty ? null : query);
      final List<dynamic> events;
      final bool hasOlder;
      try {
        final res = await _client.get(uri).timeout(_timeout);
        if (res.statusCode != 200) return null;
        final decoded = cbor.decode(res.bodyBytes);
        if (decoded is! Map) return null;
        events = decoded['events'] as List<dynamic>? ?? const [];
        hasOlder = (decoded['has_older'] as bool?) ?? false;
      } catch (_) {
        return null;
      }
      for (final e in events) {
        if (e is Map && e['id'] is String) ids.add(e['id'] as String);
      }
      if (!hasOlder || events.isEmpty) return ids;
      final oldest = events.last as Map;
      until = oldest['created_at'] as int?;
      untilId = oldest['id'] as String?;
      if (until == null || untilId == null) return ids;
    }
    developer.log(
      'relay manifest paging hit $kMaxManifestPages-page cap; '
      'continuing with a partial id set',
      name: 'relay_push',
    );
    return ids;
  }

  /// All media hashes the Relay holds, paging `/media-manifest` to
  /// completion. Null on any failure (the caller retries next pass).
  Future<Set<String>?> _relayMediaHashes(_RelayCtx ctx) async {
    final hashes = <String>{};
    String? after;
    for (var page = 0; page < kMaxManifestPages; page++) {
      final RelayMediaManifestPage result;
      try {
        result = await _push.fetchMediaManifest(
          relayBaseUrl: ctx.baseUrl,
          ownerPubkeyBytes: ctx.pubkeyBytes,
          ownerSecretKey: ctx.secretKey,
          after: after,
        );
      } catch (e) {
        developer.log('media-manifest fetch failed: $e', name: 'relay_push');
        return null;
      }
      hashes.addAll(result.hashes);
      if (!result.hasOlder || result.hashes.isEmpty) return hashes;
      after = result.hashes.last;
    }
    developer.log(
      'relay media-manifest paging hit $kMaxManifestPages-page cap; '
      'continuing with a partial hash set',
      name: 'relay_push',
    );
    return hashes;
  }
}

class _RelayCtx {
  _RelayCtx({
    required this.relayId,
    required this.baseUrl,
    required this.pubkey,
    required this.pubkeyBytes,
    required this.secretKey,
    required this.backfillComplete,
  });
  final String relayId;
  final String baseUrl;
  final String pubkey;
  final Uint8List pubkeyBytes;
  final Uint8List secretKey;
  final bool backfillComplete;
}
