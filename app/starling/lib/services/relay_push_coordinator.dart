import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../sync/manifest_pager.dart';
import 'clock.dart';
import 'relay_push_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Cap one `POST /events` batch: whichever of these trips first closes the
/// chunk. ~100 text posts ≈ 200 KB stays far under the relay's 4 MiB body
/// limit and keeps a single Tor request inside the 30s timeout; a mid-
/// backfill failure re-sends at most one chunk (inserts are idempotent).
const int kPushBatchMaxItems = 100;
const int kPushBatchMaxBytes = 1 << 20; // 1 MiB

/// Max ids/hashes per delete request. Matches the relay contract
/// (`relay-spec.md`: client chunks ≤500/req).
const int kDeleteBatchMaxItems = 500;

/// A4: a full reconcile (manifest paging over Tor + loading every own
/// event) runs at most this often while the relay is converged and local
/// state hasn't changed. Local changes, a prior failure, or an explicit
/// backfill bypass the cooldown.
const Duration kReconcileCooldown = Duration(minutes: 10);

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
/// Received comments/likes on own posts reach the relay via [reconcile]
/// ONLY — there is deliberately no immediate mirror when one arrives, so
/// they show up on the relay tier within a reconcile tick (~a minute),
/// not instantly (A12).
///
/// `relayBackfillComplete` is flipped by EITHER pass once events and media
/// have both converged, so a backfill stranded by one transport error
/// (D2) heals on the next reconcile instead of showing "syncing…" forever.
/// A pass that finds real divergence (rejected pushes, failed deletes)
/// un-flips it (A5); an unreachable relay leaves it alone.
///
/// Health (A7): every pass records `lastPushAt` (verified success, error
/// cleared) or `lastError` on the paired-relay row, so the settings screen
/// can tell a relay that 507s/401s forever from one still backfilling.
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
    Clock clock = const SystemClock(),
    Duration timeout = const Duration(seconds: 30),
  }) : _push = pushService,
       _storage = storage,
       _client = relayClient,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _mediaBytesLookup = mediaBytesLookup,
       _clock = clock,
       _timeout = timeout;

  final RelayPushService _push;
  final StorageService _storage;
  final http.Client _client;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final Future<Uint8List?> Function(String hash) _mediaBytesLookup;
  final Clock _clock;
  final Duration _timeout;

  /// A4: the 60s sync tick can fire while a slow Tor reconcile is still
  /// paging — overlapping passes double-push during backfill. Mirrors
  /// `SyncPump`'s guard.
  bool _running = false;

  /// A4 converged short-circuit state: whether the last completed pass
  /// verified convergence, the local-state signature it saw, and when it
  /// ran. While all three hold (and the cooldown hasn't lapsed) the full
  /// Tor manifest paging is skipped.
  bool _lastPassConverged = false;
  int? _lastLocalSig;
  int _lastFullPassAt = 0;

  /// Push a freshly-published event (+ its media) to the paired Relay.
  /// A kind=6 tombstone also withdraws its target (and the target's
  /// exclusively-referenced media) from the relay immediately — the relay
  /// must stop serving a deleted post without waiting for the next
  /// reconcile tick.
  Future<void> pushPublished(Event signed, Uint8List encryptedBytes) async {
    await _withRelay((ctx) async {
      try {
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
      } catch (e) {
        await _storage.recordRelayError(ctx.relayId, e.toString());
        rethrow; // _withRelay logs.
      }
      final failures = await _pushMediaHashes({
        for (final m in signed.media) m.hash,
      }, ctx);
      if (signed.kind == EventKind.delete) {
        await _deleteTombstonedTarget(signed, ctx);
      }
      await _storage.recordRelayPush(ctx.relayId, _clock.nowUnixSeconds());
      developer.log(
        'relay push published ${signed.id} media=${signed.media.length} '
        'mediaFailures=$failures',
        name: 'relay_push',
      );
    });
  }

  /// Best-effort immediate withdrawal of a freshly-tombstoned target.
  /// Failures are logged and left to the deletion-aware reconcile.
  Future<void> _deleteTombstonedTarget(Event tombstone, _RelayCtx ctx) async {
    final ref = tombstone.ref;
    if (ref == null || ref.isEmpty) return;
    try {
      await _push.deleteEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        ids: [ref],
      );
      // The target's media dies with it — unless a live event still
      // references a hash (shared media survives its deleted sibling).
      final events = await _storage.getEvents(pubkey: ctx.pubkey);
      final dead = _deadState(events, ctx.pruneBefore);
      Event? target;
      for (final e in events) {
        if (e.id == ref) {
          target = e;
          break;
        }
      }
      final exclusive = <String>[
        for (final m in target?.media ?? const <MediaRef>[])
          if (m.hash.isNotEmpty && dead.deadOnlyHashes.contains(m.hash))
            m.hash,
      ];
      await _push.deleteMedia(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        hashes: exclusive,
      );
    } catch (e) {
      developer.log(
        'immediate tombstone delete failed (reconcile heals): $e',
        name: 'relay_push',
      );
    }
  }

  /// One-shot at pair time: the relay manifest is empty, so the diff IS
  /// the full history push. Always runs in full (no short-circuit).
  Future<void> backfill() => _reconcileAndMark('backfill', force: true);

  /// Self-heal: push any own events / media blobs the Relay doesn't hold.
  Future<void> reconcile() => _reconcileAndMark('reconcile');

  // --- internals ---

  Future<void> _reconcileAndMark(String what, {bool force = false}) async {
    if (_running) {
      developer.log('relay $what skipped: pass in flight', name: 'relay_push');
      return;
    }
    _running = true;
    try {
      await _withRelay((ctx) async {
        final events = await _storage.getEvents(pubkey: ctx.pubkey);
        final localSig = _localStateSignature(events, ctx.pruneBefore);
        final now = _clock.nowUnixSeconds();
        // A4 short-circuit: the last pass verified convergence and nothing
        // local changed since — skip the Tor round trips until the
        // cooldown lapses (the periodic full pass still catches relay-side
        // loss).
        if (!force &&
            _lastPassConverged &&
            localSig == _lastLocalSig &&
            now - _lastFullPassAt < kReconcileCooldown.inSeconds) {
          developer.log(
            'relay $what short-circuited: converged, no local changes',
            name: 'relay_push',
          );
          return;
        }

        bool? converged;
        String? error;
        try {
          (converged, error) = await _syncToRelay(ctx, events);
        } catch (e) {
          _lastPassConverged = false;
          await _storage.recordRelayError(ctx.relayId, e.toString());
          rethrow; // _withRelay logs.
        }
        if (converged == null) {
          // Indeterminate (relay unreachable): NOT divergence — leave the
          // backfill flag alone, just surface the error (A7).
          _lastPassConverged = false;
          if (error != null) {
            await _storage.recordRelayError(ctx.relayId, error);
          }
          return;
        }
        _lastPassConverged = converged;
        _lastLocalSig = localSig;
        _lastFullPassAt = now;
        if (converged) {
          await _storage.recordRelayPush(ctx.relayId, now);
          if (!ctx.backfillComplete) {
            await _storage.markRelayBackfillComplete(ctx.relayId);
            developer.log('relay $what complete', name: 'relay_push');
          }
        } else {
          if (error != null) {
            await _storage.recordRelayError(ctx.relayId, error);
          }
          if (ctx.backfillComplete) {
            // A5: verified divergence un-flips the flag so the UI reads
            // "syncing" until the relay converges again.
            await _storage.clearRelayBackfillComplete(ctx.relayId);
          }
        }
      });
    } finally {
      _running = false;
    }
  }

  /// Cheap fingerprint of the local state a relay pass depends on: the
  /// own-event id set (adds AND removes) plus the prune horizon. Media
  /// derives from events, so id changes cover it.
  int _localStateSignature(List<Event> events, int pruneBefore) =>
      Object.hash(pruneBefore, Object.hashAll([for (final e in events) e.id]));

  /// Diff the relay's events + media against local state, push what's
  /// missing, and delete what's deliberately dead. Returns `(converged,
  /// error)`: converged `true` when the relay verifiably converged (events
  /// pushed with zero rejections, media diffed, zero push OR delete
  /// failures — a failed delete means the relay still serves a deleted
  /// post, which must block `relayBackfillComplete`); `false` on verified
  /// divergence; `null` when the relay was unreachable and nothing can be
  /// concluded. Event push errors propagate; media errors are per-blob.
  Future<(bool?, String?)> _syncToRelay(
    _RelayCtx ctx,
    List<Event> events,
  ) async {
    final present = await _relayEventIds(ctx.baseUrl);
    if (present == null) {
      return (null, 'relay unreachable (manifest fetch failed)');
    }

    var pruneBefore = ctx.pruneBefore;
    var dead = _deadState(events, pruneBefore);
    var missingItems = await _missingItems(events, present, dead.deadIds);

    // Push what's missing. On a 507 the relay is full: age the oldest
    // posts off it (persisting the horizon FIRST), then retry ONCE. A
    // second 507 means the HOST disk is full — give up this pass, no loop.
    var rejected = 0;
    for (var attempt = 0; ; attempt++) {
      try {
        if (missingItems.isNotEmpty) {
          rejected = await _pushEventsChunked(missingItems, ctx);
          developer.log(
            'relay sync pushed ${missingItems.length} missing events '
            '(rejected=$rejected)',
            name: 'relay_push',
          );
        }
        break;
      } on RelayPushException catch (e) {
        if (e.statusCode != 507 || attempt > 0) rethrow;
        final horizon = await _pruneForSpace(
          events: events,
          missing: missingItems,
          present: present,
          dead: dead,
          ctx: ctx,
        );
        if (horizon == null) rethrow; // nothing prunable — give up
        pruneBefore = horizon;
        dead = _deadState(events, pruneBefore);
        missingItems = await _missingItems(events, present, dead.deadIds);
      }
    }

    // Withdraw deliberately-dead events the relay still serves: tombstoned
    // targets and horizon-pruned posts. Relay-extra ids that are NEITHER
    // are never deleted — after a recovery-phrase restore the relay may
    // hold history the phone lost, and that copy must survive.
    var deleteFailures = 0;
    final deadPresent = present.intersection(dead.deadIds).toList();
    try {
      await _deleteEventsChunked(deadPresent, ctx);
    } catch (e) {
      deleteFailures++;
      developer.log('relay event delete failed: $e', name: 'relay_push');
    }

    // D8, deletion-aware: expected = hashes referenced by LIVE own events
    // only (payload-less pre-v2 events included — pushing their media is
    // harmless); dead-only hashes still on the relay are deleted. Shared
    // media survives a deleted sibling: a hash any live event references
    // is never in the dead-only set.
    final relayHashes = await _relayMediaHashes(ctx);
    if (relayHashes == null) {
      return (null, 'relay unreachable (media manifest fetch failed)');
    }
    final pushFailures = await _pushMediaHashes(
      dead.liveHashes.difference(relayHashes),
      ctx,
    );
    final deadMedia = dead.deadOnlyHashes.intersection(relayHashes).toList();
    try {
      await _deleteMediaChunked(deadMedia, ctx);
    } catch (e) {
      deleteFailures++;
      developer.log('relay media delete failed: $e', name: 'relay_push');
    }
    if (rejected == 0 && pushFailures == 0 && deleteFailures == 0) {
      return (true, null);
    }
    return (
      false,
      'sync incomplete: $rejected rejected, '
          '$pushFailures media failures, $deleteFailures delete failures',
    );
  }

  /// The events to push: everything local the relay lacks, EXCEPT
  /// room-scoped kinds (membership-encrypted, never relay-served),
  /// dead ids (tombstoned targets / pruned posts — re-pushing would undo
  /// deletion), and pre-v2 events with no stored wire payload. Tombstones
  /// themselves are never dead, so they always reach the relay.
  Future<List<RelayPushItem>> _missingItems(
    List<Event> events,
    Set<String> present,
    Set<String> deadIds,
  ) async {
    final items = <RelayPushItem>[];
    for (final e in events) {
      if (e.kind.isRoomScoped) continue;
      if (deadIds.contains(e.id)) continue;
      if (present.contains(e.id)) continue;
      final payload = await _storage.getEncryptedPayload(e.id);
      if (payload == null) continue;
      items.add(
        RelayPushItem(
          id: e.id,
          encryptedEvent: EncryptedEvent.fromBytes(payload),
        ),
      );
    }
    return items;
  }

  /// Prune-on-507 (Phase 3c): free relay space by aging the OLDEST own
  /// posts (kind=1 only — profiles, tombstones, comments, likes are tiny
  /// and structurally significant) off the relay. Accumulates ~2× the
  /// bytes the failed push needed, persists `relayPruneBefore =
  /// newestPruned.createdAt + 1` BEFORE issuing any delete (a crash
  /// re-derives the same pruned set from the horizon), then deletes the
  /// pruned ids the relay holds. Pruned posts stay on the phone — they
  /// only age off the relay window.
  ///
  /// Returns the new horizon, or null when nothing is prunable. Removes
  /// the deleted ids from [present] so the caller's later delete pass
  /// doesn't re-send them.
  Future<int?> _pruneForSpace({
    required List<Event> events,
    required List<RelayPushItem> missing,
    required Set<String> present,
    required _DeadState dead,
    required _RelayCtx ctx,
  }) async {
    // Bytes the failed push needed, in stored-wire terms (what the relay's
    // cap actually counts).
    final needed = missing.fold<int>(
      0,
      (sum, i) => sum + i.encryptedEvent.toBytes().length,
    );
    // Never prune what we're trying to push — aging the new post off to
    // make room for itself converges to serving nothing.
    final missingIds = {for (final i in missing) i.id};
    final candidates =
        events
            .where(
              (e) =>
                  e.kind == EventKind.post &&
                  !dead.deadIds.contains(e.id) &&
                  !missingIds.contains(e.id),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var accumulated = 0;
    Event? newestPruned;
    for (final e in candidates) {
      if (accumulated >= needed * 2) break;
      final payload = await _storage.getEncryptedPayload(e.id);
      if (payload == null) continue;
      accumulated += payload.length;
      newestPruned = e;
    }
    if (newestPruned == null) return null;

    final horizon = newestPruned.createdAt + 1;
    await _storage.setRelayPruneBefore(ctx.relayId, horizon);
    final prunedIds = <String>{
      for (final e in candidates)
        if (e.createdAt < horizon) e.id,
    };
    final prunedPresent = present.intersection(prunedIds).toList();
    await _deleteEventsChunked(prunedPresent, ctx);
    present.removeAll(prunedPresent);
    developer.log(
      'relay 507: pruned ${prunedPresent.length} posts (horizon=$horizon) '
      'to free ~$accumulated bytes',
      name: 'relay_push',
    );
    return horizon;
  }

  /// Delete event ids in ≤[kDeleteBatchMaxItems] requests. Throws on the
  /// first failed chunk (already-deleted chunks are idempotent on replay).
  Future<void> _deleteEventsChunked(List<String> ids, _RelayCtx ctx) async {
    for (var start = 0; start < ids.length; start += kDeleteBatchMaxItems) {
      final end = start + kDeleteBatchMaxItems > ids.length
          ? ids.length
          : start + kDeleteBatchMaxItems;
      await _push.deleteEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        ids: ids.sublist(start, end),
      );
    }
  }

  /// [_deleteEventsChunked] for media hashes.
  Future<void> _deleteMediaChunked(List<String> hashes, _RelayCtx ctx) async {
    for (var start = 0; start < hashes.length; start += kDeleteBatchMaxItems) {
      final end = start + kDeleteBatchMaxItems > hashes.length
          ? hashes.length
          : start + kDeleteBatchMaxItems;
      await _push.deleteMedia(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        hashes: hashes.sublist(start, end),
      );
    }
  }

  /// Classify local state for deletion (Phase 3): an own event is DEAD
  /// when the phone holds a tombstone ref'ing it, or it's a post under the
  /// persisted prune horizon. Tombstones themselves are never dead. A
  /// media hash is dead-only when every event referencing it is dead —
  /// shared media referenced by any live event survives.
  _DeadState _deadState(List<Event> events, int pruneBefore) {
    final tombstoneIds = <String>{};
    final tombstonedRefs = <String>{};
    for (final e in events) {
      if (e.kind == EventKind.delete) {
        tombstoneIds.add(e.id);
        final ref = e.ref;
        if (ref != null && ref.isNotEmpty) tombstonedRefs.add(ref);
      }
    }
    final deadIds = <String>{
      // Tombstoned targets — kept even when the phone no longer holds the
      // row (present ∩ dead still withdraws them from the relay).
      ...tombstonedRefs,
      // Horizon-pruned: own POSTS only ever age off.
      for (final e in events)
        if (e.kind == EventKind.post && e.createdAt < pruneBefore) e.id,
    }..removeAll(tombstoneIds);
    final liveHashes = <String>{};
    final deadHashes = <String>{};
    for (final e in events) {
      final sink = deadIds.contains(e.id) ? deadHashes : liveHashes;
      for (final m in e.media) {
        if (m.hash.isNotEmpty) sink.add(m.hash);
      }
    }
    return _DeadState(
      deadIds: deadIds,
      liveHashes: liveHashes,
      deadOnlyHashes: deadHashes.difference(liveHashes),
    );
  }

  /// Push [items] as bounded batches — one signed POST each. Throws on the
  /// first failed batch (already-sent chunks are idempotent on re-push).
  /// Returns the total `rejected` count across receipts (A5): items the
  /// relay refused as malformed, which a re-push can never heal.
  Future<int> _pushEventsChunked(List<RelayPushItem> items, _RelayCtx ctx) async {
    var rejected = 0;
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
      final receipt = await _push.pushEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        items: items.sublist(start, end),
      );
      rejected += receipt.rejected;
      start = end;
    }
    return rejected;
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
          pruneBefore: relay.relayPruneBefore,
        ),
      );
    } catch (e) {
      developer.log('relay push skipped: $e', name: 'relay_push');
    }
  }

  /// All event ids the Relay holds, paging `/manifest` to completion via
  /// the shared keyset pager (A10 — one paging loop for phone and relay
  /// manifests). Null if the Relay is unreachable or answers garbage; a
  /// pager cap-hit yields a partial id set, which only defers deletions.
  Future<Set<String>?> _relayEventIds(String baseUrl) async {
    try {
      final pages = await pageManifestToCompletion(({
        int? until,
        String? untilId,
      }) async {
        final query = <String, String>{
          if (until != null) 'until': until.toString(),
          if (until != null && untilId != null) 'until_id': untilId,
        };
        final uri = Uri.parse(
          '$baseUrl/manifest',
        ).replace(queryParameters: query.isEmpty ? null : query);
        final res = await _client.get(uri).timeout(_timeout);
        if (res.statusCode != 200) {
          throw RelayPushException(
            'manifest fetch failed: ${res.statusCode}',
            statusCode: res.statusCode,
          );
        }
        final decoded = cbor.decode(res.bodyBytes);
        if (decoded is! Map) {
          throw RelayPushException('manifest body not a CBOR map');
        }
        return Manifest(
          pubkey: decoded['pubkey'] as String? ?? '',
          events: [
            for (final e in decoded['events'] as List<dynamic>? ?? const [])
              if (e is Map && e['id'] is String && e['created_at'] is int)
                ManifestEntry(
                  id: e['id'] as String,
                  createdAt: e['created_at'] as int,
                ),
          ],
          hasOlder: (decoded['has_older'] as bool?) ?? false,
        );
      });
      return {
        for (final page in pages)
          for (final e in page.events) e.id,
      };
    } catch (e) {
      developer.log('relay manifest paging failed: $e', name: 'relay_push');
      return null;
    }
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
    required this.pruneBefore,
  });
  final String relayId;
  final String baseUrl;
  final String pubkey;
  final Uint8List pubkeyBytes;
  final Uint8List secretKey;
  final bool backfillComplete;

  /// Persisted prune horizon at pass start (`PairedRelay.relayPruneBefore`).
  final int pruneBefore;
}

/// See [RelayPushCoordinator._deadState].
class _DeadState {
  _DeadState({
    required this.deadIds,
    required this.liveHashes,
    required this.deadOnlyHashes,
  });

  /// Event ids deliberately withdrawn from the relay: tombstoned targets +
  /// horizon-pruned posts. NEVER contains a tombstone's own id.
  final Set<String> deadIds;

  /// Media hashes referenced by at least one live own event.
  final Set<String> liveHashes;

  /// Media hashes referenced ONLY by dead events — safe to withdraw.
  final Set<String> deadOnlyHashes;
}
