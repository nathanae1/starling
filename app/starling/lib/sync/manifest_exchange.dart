import 'dart:math' as math;
import 'dart:typed_data';

import '../services/storage_service.dart';
import '../services/types.dart';
import 'manifest_pager.dart';
import 'sync_engine.dart' show SyncTransport;

/// Result of a manifest comparison: which event IDs the peer has that we
/// don't, and what range was inspected. May also carry an inline feed-key
/// rotation delivery from the peer (Plan 13).
class ManifestDiff {
  const ManifestDiff({
    required this.missingIds,
    required this.peerEvents,
    required this.windowSince,
    this.maxCreatedAt,
    this.hasOlder = false,
    this.newFeedKey,
    this.newConnectionCard,
  });
  final List<String> missingIds;
  final List<ManifestEntry> peerEvents;
  final int? windowSince;

  /// Max author `created_at` across the peer entries seen; null when the
  /// manifest (window) was empty. D1: the sync cursor advances to this —
  /// never to wall-clock — so it can't slide past author-time we haven't
  /// observed.
  final int? maxCreatedAt;

  /// The peer truncated the response at its page limit — the diff is
  /// incomplete and the caller should redo it as a full paged pass.
  /// Always false from [ManifestExchange.fetchAndDiffFull].
  final bool hasOlder;

  final SealedDelivery? newFeedKey;
  final SealedDelivery? newConnectionCard;
}

/// Asks a peer for its manifest, compares against our local event IDs for
/// the same author, and returns the diff. Used by [SyncEngine] to decide
/// what to fetch.
class ManifestExchange {
  ManifestExchange({
    required SyncTransport transport,
    required StorageService storage,
  })  : _transport = transport,
        _storage = storage;

  final SyncTransport _transport;
  final StorageService _storage;

  Future<ManifestDiff> fetchAndDiff(
    PeerConnection peer,
    Follow follow, {
    int? since,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  }) async {
    final windowSince = since ?? follow.lastSyncedAt;
    final manifest = await _transport.fetchManifest(
      peer,
      since: windowSince,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
      ackSig: ackSig,
    );
    if (manifest.pubkey != follow.pubkey) {
      // Peer is serving someone else's content under this connection. Drop.
      return ManifestDiff(
        missingIds: const [],
        peerEvents: const [],
        windowSince: windowSince,
      );
    }

    // Pull only the IDs we already have for this pubkey within the window.
    // We use `since` here to bound the local query to the same range the
    // manifest covers.
    final local = await _storage.getEvents(
      pubkey: follow.pubkey,
      since: windowSince,
    );
    final localIds = local.map((e) => e.id).toSet();

    final missing = <String>[];
    for (final entry in manifest.events) {
      if (!localIds.contains(entry.id)) {
        missing.add(entry.id);
      }
    }
    return ManifestDiff(
      missingIds: missing,
      peerEvents: manifest.events,
      windowSince: windowSince,
      maxCreatedAt: _maxCreatedAt(manifest.events),
      hasOlder: manifest.hasOlder,
      newFeedKey: manifest.newFeedKey,
      newConnectionCard: manifest.newConnectionCard,
    );
  }

  /// Full (un-windowed) diff: pages the peer's ENTIRE manifest via the
  /// `until`/`until_id` keyset cursor and diffs against all local ids for
  /// the pubkey (D1). This is what catches events that arrived at the
  /// store out of author-time order — a late-healed relay push, a
  /// redistributed comment — which no `since`-window can see.
  ///
  /// Acks and pending deliveries ride the first page only; the returned
  /// `windowSince` is the oldest missing entry's `created_at`, bounding
  /// the follow-up `GET /events` fetch to the actual gap. (That fetch is
  /// server-capped at ~500 payloads oldest-first, so a larger residual
  /// gap finishes over subsequent passes.)
  Future<ManifestDiff> fetchAndDiffFull(
    PeerConnection peer,
    Follow follow, {
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  }) async {
    var first = true;
    final pages = await pageManifestToCompletion(
      ({int? until, String? untilId}) {
        final attachAcks = first;
        first = false;
        return _transport.fetchManifest(
          peer,
          until: until,
          untilId: untilId,
          requesterPubkey: attachAcks ? requesterPubkey : null,
          ackRotationAt: attachAcks ? ackRotationAt : null,
          cardSeenAt: attachAcks ? cardSeenAt : null,
          ackSig: attachAcks ? ackSig : null,
        );
      },
    );
    final firstPage = pages.first;
    if (firstPage.pubkey != follow.pubkey) {
      return const ManifestDiff(
        missingIds: [],
        peerEvents: [],
        windowSince: null,
      );
    }

    final peerEvents = [for (final p in pages) ...p.events];
    final local = await _storage.getEvents(pubkey: follow.pubkey);
    final localIds = local.map((e) => e.id).toSet();

    final missing = <String>[];
    int? oldestMissingAt;
    for (final entry in peerEvents) {
      if (localIds.contains(entry.id)) continue;
      missing.add(entry.id);
      oldestMissingAt = oldestMissingAt == null
          ? entry.createdAt
          : math.min(oldestMissingAt, entry.createdAt);
    }
    return ManifestDiff(
      missingIds: missing,
      peerEvents: peerEvents,
      windowSince: oldestMissingAt,
      maxCreatedAt: _maxCreatedAt(peerEvents),
      newFeedKey: firstPage.newFeedKey,
      newConnectionCard: firstPage.newConnectionCard,
    );
  }

  int? _maxCreatedAt(List<ManifestEntry> entries) {
    int? max;
    for (final e in entries) {
      if (max == null || e.createdAt > max) max = e.createdAt;
    }
    return max;
  }
}
