import '../services/storage_service.dart';
import '../services/types.dart';
import 'sync_engine.dart' show SyncTransport;

/// Result of a manifest comparison: which event IDs the peer has that we
/// don't, and what range was inspected. May also carry an inline feed-key
/// rotation delivery from the peer (Plan 13).
class ManifestDiff {
  const ManifestDiff({
    required this.missingIds,
    required this.peerEvents,
    required this.windowSince,
    this.newFeedKey,
    this.newConnectionCard,
  });
  final List<String> missingIds;
  final List<ManifestEntry> peerEvents;
  final int? windowSince;
  final RotatedFeedKeyDelivery? newFeedKey;
  final ConnectionCardDelivery? newConnectionCard;
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
  }) async {
    final windowSince = since ?? follow.lastSyncedAt;
    final manifest = await _transport.fetchManifest(
      peer,
      since: windowSince,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
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
      newFeedKey: manifest.newFeedKey,
      newConnectionCard: manifest.newConnectionCard,
    );
  }
}
