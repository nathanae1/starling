import 'dart:async';
import 'dart:typed_data';

import '../../models/models.dart';
import '../storage_service.dart';
import '../types.dart';

/// In-memory mock StorageService for testing without a database.
class MockStorageService implements StorageService {
  Identity? _identity;
  final Map<String, Follow> _follows = {};
  final Map<String, Event> _events = {};
  final Map<String, Uint8List> _encryptedPayloads = {};
  final Map<String, CachedMedia> _mediaCache = {};
  final List<FollowRequest> _inboundRequests = [];
  final List<FollowRequest> _outboundRequests = [];
  final List<QueuedEvent> _queue = [];
  final Set<String> _savedEventIds = {};
  final Map<String, int> _lastViewed = {};
  int _nextQueueId = 1;

  final StreamController<List<Follow>> _followsController =
      StreamController<List<Follow>>.broadcast();
  final StreamController<List<FollowRequest>> _inboundController =
      StreamController<List<FollowRequest>>.broadcast();
  final StreamController<List<FollowRequest>> _inboundFollowersController =
      StreamController<List<FollowRequest>>.broadcast();
  final StreamController<List<FollowRequest>> _outboundController =
      StreamController<List<FollowRequest>>.broadcast();

  List<Follow> _snapshotFollows() =>
      _follows.values.where((f) => f.status == 'active').toList();
  List<FollowRequest> _snapshotInbound() =>
      _inboundRequests.where((r) => r.status == 'pending').toList();
  List<FollowRequest> _snapshotInboundFollowers() =>
      _inboundRequests.where((r) => r.status != 'pending').toList();
  List<FollowRequest> _snapshotOutbound() => _outboundRequests.toList();

  void _emitFollows() => _followsController.add(_snapshotFollows());
  void _emitInbound() {
    _inboundController.add(_snapshotInbound());
    _inboundFollowersController.add(_snapshotInboundFollowers());
  }
  void _emitOutbound() => _outboundController.add(_snapshotOutbound());

  /// Releases broadcast controllers. Call from tearDown when the test
  /// instance is no longer needed.
  Future<void> dispose() async {
    // Never await these: a broadcast close() only completes once the done
    // event reaches every listener, and listeners subscribed inside a
    // testWidgets FakeAsync zone stop being pumped after the test body —
    // awaiting would deadlock teardown until the 10-minute test timeout.
    unawaited(_followsController.close());
    unawaited(_inboundController.close());
    unawaited(_inboundFollowersController.close());
    unawaited(_outboundController.close());
  }

  // --- Identity ---

  @override
  Future<Identity?> getIdentity() async => _identity;

  @override
  Future<void> saveIdentity(Identity identity) async {
    _identity = identity;
  }

  // --- Follows ---

  @override
  Future<List<Follow>> getFollows() async =>
      _follows.values.where((f) => f.status == 'active').toList();

  @override
  Stream<List<Follow>> watchFollows() async* {
    yield _snapshotFollows();
    yield* _followsController.stream;
  }

  @override
  Future<Follow?> getFollow(String pubkey) async => _follows[pubkey];

  @override
  Future<void> saveFollow(Follow follow) async {
    _follows[follow.pubkey] = follow;
    _emitFollows();
  }

  @override
  Future<void> removeFollow(String pubkey) async {
    _follows.remove(pubkey);
    _emitFollows();
  }

  @override
  Future<void> updateLastSynced(String pubkey, int timestamp) async {
    final follow = _follows[pubkey];
    if (follow != null) {
      _follows[pubkey] = follow.copyWith(lastSyncedAt: timestamp);
      _emitFollows();
    }
  }

  @override
  Future<void> updateLastFullSynced(String pubkey, int timestamp) async {
    final follow = _follows[pubkey];
    if (follow != null) {
      _follows[pubkey] = follow.copyWith(lastFullSyncAt: timestamp);
      _emitFollows();
    }
  }

  @override
  Future<void> setLastDecryptFailureAt(
    String pubkey,
    int? timestamp,
  ) async {
    final follow = _follows[pubkey];
    if (follow != null) {
      _follows[pubkey] = follow.copyWith(
        lastDecryptFailureAt: timestamp,
        clearLastDecryptFailureAt: timestamp == null,
      );
      _emitFollows();
    }
  }

  @override
  Future<void> clearLastDecryptFailureIfSet(String pubkey) async {
    final follow = _follows[pubkey];
    if (follow != null && follow.lastDecryptFailureAt != null) {
      _follows[pubkey] = follow.copyWith(clearLastDecryptFailureAt: true);
      _emitFollows();
    }
  }

  // --- Events ---

  @override
  Future<List<Event>> getEvents({
    String? pubkey,
    int? since,
    int? until,
    String? untilId,
    int? limit,
  }) async {
    var results = _events.values.toList();
    if (pubkey != null) {
      results = results.where((e) => e.pubkey == pubkey).toList();
    }
    if (since != null) {
      results = results.where((e) => e.createdAt >= since).toList();
    }
    if (until != null) {
      results = untilId != null
          // Strict keyset cursor — see StorageService.getEvents.
          ? results
              .where((e) =>
                  e.createdAt < until ||
                  (e.createdAt == until && e.id.compareTo(untilId) < 0))
              .toList()
          : results.where((e) => e.createdAt <= until).toList();
    }
    results.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    if (limit != null) {
      results = results.take(limit).toList();
    }
    return results;
  }

  @override
  Future<Event?> getEvent(String id) async => _events[id];

  @override
  Future<void> saveEvent(Event event) async {
    _events[event.id] = event;
  }

  @override
  Future<void> saveOwnEventWithEncrypted(
    Event event,
    Uint8List encryptedPayload,
  ) async {
    _events[event.id] = event;
    _encryptedPayloads[event.id] = encryptedPayload;
  }

  @override
  Future<Uint8List?> getEncryptedPayload(String id) async =>
      _encryptedPayloads[id];

  @override
  Future<void> deleteEvent(String id) async {
    _events.remove(id);
    _encryptedPayloads.remove(id);
  }

  @override
  Future<List<Event>> getFeedEvents({int? since, int? limit}) async {
    final followedPubkeys = _follows.values
        .where((f) => f.status == 'active')
        .map((f) => f.pubkey)
        .toSet();
    final ownPubkey = _identity?.pubkey;

    final tombstoned = _tombstonedIds();

    var results = _events.values.where((e) {
      final fromIncludedAuthor =
          e.pubkey == ownPubkey || followedPubkeys.contains(e.pubkey);
      return fromIncludedAuthor &&
          e.kind.value == 1 &&
          !tombstoned.contains(e.id);
    }).toList();

    if (since != null) {
      results = results.where((e) => e.createdAt >= since).toList();
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null) {
      results = results.take(limit).toList();
    }
    return results;
  }

  @override
  Future<List<Event>> getProfilePosts(String pubkey, {int? limit}) async {
    final tombstoned = _tombstonedIds(authorFilter: pubkey);
    var results = _events.values.where((e) {
      return e.pubkey == pubkey &&
          e.kind.value == 1 &&
          !tombstoned.contains(e.id);
    }).toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null) {
      results = results.take(limit).toList();
    }
    return results;
  }

  @override
  Future<List<Event>> getEventsByRef(String refId, {EventKind? kind}) async {
    var results = _events.values.where((e) => e.ref == refId).toList();
    if (kind != null) {
      results = results.where((e) => e.kind == kind).toList();
    }
    results.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return results;
  }

  @override
  Future<List<Event>> getOwnAndIncomingRefs(
    String ownerPubkey, {
    int? since,
    int? limit,
  }) async {
    final ownIds = _events.values
        .where((e) => e.pubkey == ownerPubkey)
        .map((e) => e.id)
        .toSet();
    var results = _events.values.where((e) {
      return e.pubkey == ownerPubkey ||
          (e.ref != null && ownIds.contains(e.ref));
    }).toList();
    if (since != null) {
      results = results.where((e) => e.createdAt >= since).toList();
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null) {
      results = results.take(limit).toList();
    }
    return results;
  }

  @override
  Future<bool> isEventSaved(String id) async => _savedEventIds.contains(id);

  @override
  Future<void> setEventSaved(String id, bool saved) async {
    if (saved) {
      _savedEventIds.add(id);
    } else {
      _savedEventIds.remove(id);
    }
  }

  @override
  Future<void> setEventLastViewed(String id, int timestamp) async {
    _lastViewed[id] = timestamp;
  }

  /// Returns the set of event ids that have a kind=6 tombstone from the
  /// same author. If [authorFilter] is set, restricts the lookup.
  Set<String> _tombstonedIds({String? authorFilter}) {
    final byAuthor = <String, Set<String>>{};
    for (final e in _events.values) {
      if (e.kind.value != 6) continue;
      if (e.ref == null) continue;
      if (authorFilter != null && e.pubkey != authorFilter) continue;
      byAuthor.putIfAbsent(e.pubkey, () => <String>{}).add(e.ref!);
    }
    final out = <String>{};
    for (final e in _events.values) {
      if (byAuthor[e.pubkey]?.contains(e.id) ?? false) {
        out.add(e.id);
      }
    }
    return out;
  }

  // --- Media cache ---

  @override
  Future<CachedMedia?> getMedia(String hash) async => _mediaCache[hash];

  @override
  Future<void> saveMedia(CachedMedia media) async {
    _mediaCache[media.hash] = media;
  }

  @override
  Future<void> deleteMedia(String hash) async {
    _mediaCache.remove(hash);
  }

  @override
  Future<int> getMediaCacheSize() async {
    var total = 0;
    for (final m in _mediaCache.values) {
      total += m.size;
    }
    return total;
  }

  @override
  Future<void> evictMedia(int targetSize) async {
    final sorted = _mediaCache.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    var totalSize = await getMediaCacheSize();
    for (final media in sorted) {
      if (totalSize <= targetSize) break;
      _mediaCache.remove(media.hash);
      totalSize -= media.size;
    }
  }

  // --- Followers (Plan 13) ---

  @override
  Future<List<String>> getAcceptedFollowerPubkeys() async => _inboundRequests
      .where((r) => r.status == 'accepted')
      .map((r) => r.pubkey)
      .toList();

  @override
  Future<bool> isAcceptedFollower(String pubkey) async {
    for (final r in _inboundRequests) {
      if (r.pubkey == pubkey) return r.status == 'accepted';
    }
    return false;
  }

  @override
  Future<void> removeAcceptedFollower(String pubkey) async {
    _inboundRequests.removeWhere((r) => r.pubkey == pubkey);
    _emitInbound();
  }

  // --- Feed key history (Plan 13) ---

  final List<RetiredFeedKey> _feedKeyHistory = [];

  @override
  Future<void> appendFeedKeyHistory({
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  }) async {
    _feedKeyHistory.add(RetiredFeedKey(
      feedKey: feedKey,
      feedKeyEpoch: feedKeyEpoch,
      validFrom: validFrom,
      validUntil: validUntil,
    ));
  }

  @override
  Future<RetiredFeedKey?> retiredFeedKeyAt(int timestamp) async {
    for (final h in _feedKeyHistory) {
      if (h.validFrom <= timestamp && timestamp < h.validUntil) return h;
    }
    return null;
  }

  @override
  Future<List<RetiredFeedKey>> getFeedKeyHistory() async {
    final sorted = [..._feedKeyHistory];
    sorted.sort((a, b) => a.validFrom.compareTo(b.validFrom));
    return sorted;
  }

  // --- Per-follow feed-key history (MegOLM archive) ---

  final Map<String, List<RetiredFeedKey>> _followFeedKeyHistory = {};

  @override
  Future<void> appendFollowFeedKeyHistory({
    required String followPubkey,
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  }) async {
    _followFeedKeyHistory
        .putIfAbsent(followPubkey, () => [])
        .add(RetiredFeedKey(
          feedKey: feedKey,
          feedKeyEpoch: feedKeyEpoch,
          validFrom: validFrom,
          validUntil: validUntil,
        ));
  }

  @override
  Future<List<RetiredFeedKey>> getFollowFeedKeyHistory(
    String followPubkey,
  ) async {
    final list = _followFeedKeyHistory[followPubkey];
    if (list == null) return const [];
    final sorted = [...list];
    sorted.sort((a, b) => a.validFrom.compareTo(b.validFrom));
    return sorted;
  }

  // --- Pending key distributions (Plan 13) ---

  final List<PendingKeyDistribution> _pendingDistributions = [];
  final Set<String> _deliveredKeys = {}; // "pubkey|createdAt" markers

  String _distKey(String pubkey, int createdAt) => '$pubkey|$createdAt';

  @override
  Future<void> addPendingKeyDistribution({
    required String targetPubkey,
    required Uint8List encryptedFeedKey,
    required Uint8List nonce,
    required int createdAt,
  }) async {
    _pendingDistributions
      ..removeWhere(
        (d) => d.targetPubkey == targetPubkey && d.createdAt == createdAt,
      )
      ..add(PendingKeyDistribution(
        targetPubkey: targetPubkey,
        encryptedFeedKey: encryptedFeedKey,
        nonce: nonce,
        createdAt: createdAt,
      ));
    _deliveredKeys.remove(_distKey(targetPubkey, createdAt));
  }

  @override
  Future<PendingKeyDistribution?> latestPendingDistributionFor(
    String targetPubkey,
  ) async {
    PendingKeyDistribution? best;
    for (final d in _pendingDistributions) {
      if (d.targetPubkey != targetPubkey) continue;
      if (_deliveredKeys.contains(_distKey(d.targetPubkey, d.createdAt))) {
        continue;
      }
      if (best == null || d.createdAt > best.createdAt) best = d;
    }
    return best;
  }

  @override
  Future<void> markDistributionsDelivered(
    String targetPubkey,
    int upTo,
  ) async {
    for (final d in _pendingDistributions) {
      if (d.targetPubkey == targetPubkey && d.createdAt <= upTo) {
        _deliveredKeys.add(_distKey(d.targetPubkey, d.createdAt));
      }
    }
  }

  @override
  Future<void> clearPendingDistributionsFor(String targetPubkey) async {
    _pendingDistributions.removeWhere((d) => d.targetPubkey == targetPubkey);
    _deliveredKeys.removeWhere((k) => k.startsWith('$targetPubkey|'));
  }

  // --- Paired relay + card distributions (Plan 15) ---

  PairedRelay? _pairedRelay;
  final List<PendingCardDistribution> _pendingCards = [];
  final Set<String> _deliveredCards = {}; // "pubkey|createdAt" markers

  @override
  Future<PairedRelay?> getPairedRelay() async => _pairedRelay;

  @override
  Future<void> setPairedRelay({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
  }) async {
    _pairedRelay = PairedRelay(
      relayId: relayId,
      relayOnion: relayOnion,
      pairedAt: pairedAt,
    );
  }

  @override
  Future<void> markRelayBackfillComplete(String relayId) async {
    final relay = _pairedRelay;
    if (relay != null && relay.relayId == relayId) {
      _pairedRelay = PairedRelay(
        relayId: relay.relayId,
        relayOnion: relay.relayOnion,
        pairedAt: relay.pairedAt,
        backfillComplete: true,
      );
    }
  }

  @override
  Future<void> clearPairedRelay() async {
    _pairedRelay = null;
  }

  @override
  Future<void> queueCardDistribution({
    required String targetPubkey,
    required Uint8List encryptedCard,
    required Uint8List nonce,
    required int createdAt,
  }) async {
    _pendingCards
      ..removeWhere(
        (d) => d.targetPubkey == targetPubkey && d.createdAt == createdAt,
      )
      ..add(PendingCardDistribution(
        targetPubkey: targetPubkey,
        encryptedCard: encryptedCard,
        nonce: nonce,
        createdAt: createdAt,
      ));
    _deliveredCards.remove(_distKey(targetPubkey, createdAt));
  }

  @override
  Future<PendingCardDistribution?> latestPendingCardFor(
    String targetPubkey,
  ) async {
    PendingCardDistribution? best;
    for (final d in _pendingCards) {
      if (d.targetPubkey != targetPubkey) continue;
      if (_deliveredCards.contains(_distKey(d.targetPubkey, d.createdAt))) {
        continue;
      }
      if (best == null || d.createdAt > best.createdAt) best = d;
    }
    return best;
  }

  @override
  Future<void> markCardDistributionsDelivered(
    String targetPubkey,
    int upTo,
  ) async {
    for (final d in _pendingCards) {
      if (d.targetPubkey == targetPubkey && d.createdAt <= upTo) {
        _deliveredCards.add(_distKey(d.targetPubkey, d.createdAt));
      }
    }
  }

  @override
  Future<void> clearCardDistributionsFor(String targetPubkey) async {
    _pendingCards.removeWhere((d) => d.targetPubkey == targetPubkey);
    _deliveredCards.removeWhere((k) => k.startsWith('$targetPubkey|'));
  }

  // --- Follow requests ---

  @override
  Future<List<FollowRequest>> getInboundRequests() async =>
      _inboundRequests.where((r) => r.status == 'pending').toList();

  @override
  Stream<List<FollowRequest>> watchInboundRequests() async* {
    yield _snapshotInbound();
    yield* _inboundController.stream;
  }

  @override
  Stream<List<FollowRequest>> watchInboundFollowers() async* {
    yield _snapshotInboundFollowers();
    yield* _inboundFollowersController.stream;
  }

  @override
  Future<List<FollowRequest>> getInboundRequestsByStatus(String status) async =>
      _inboundRequests.where((r) => r.status == status).toList();

  @override
  Future<FollowRequest?> getInboundRequest(String pubkey) async {
    for (final r in _inboundRequests) {
      if (r.pubkey == pubkey) return r;
    }
    return null;
  }

  @override
  Future<void> saveInboundRequest(FollowRequest request) async {
    final index = _inboundRequests.indexWhere((r) => r.pubkey == request.pubkey);
    if (index >= 0) {
      _inboundRequests[index] = request;
    } else {
      _inboundRequests.add(request);
    }
    _emitInbound();
  }

  @override
  Future<void> updateInboundRequestStatus(
    String pubkey,
    String status,
  ) async {
    final index = _inboundRequests.indexWhere((r) => r.pubkey == pubkey);
    if (index >= 0) {
      final old = _inboundRequests[index];
      _inboundRequests[index] = FollowRequest(
        pubkey: old.pubkey,
        payload: old.payload,
        createdAt: old.createdAt,
        requestTimestamp: old.requestTimestamp,
        status: status,
      );
      _emitInbound();
    }
  }

  @override
  Future<void> deleteInboundRequest(String pubkey) async {
    _inboundRequests.removeWhere((r) => r.pubkey == pubkey);
    _emitInbound();
  }

  @override
  Future<List<FollowRequest>> getOutboundRequests() async =>
      _outboundRequests.toList();

  @override
  Stream<List<FollowRequest>> watchOutboundRequests() async* {
    yield _snapshotOutbound();
    yield* _outboundController.stream;
  }

  @override
  Future<FollowRequest?> getOutboundRequest(String pubkey) async {
    for (final r in _outboundRequests) {
      if (r.pubkey == pubkey) return r;
    }
    return null;
  }

  @override
  Future<void> saveOutboundRequest(FollowRequest request) async {
    final index = _outboundRequests.indexWhere((r) => r.pubkey == request.pubkey);
    if (index >= 0) {
      _outboundRequests[index] = request;
    } else {
      _outboundRequests.add(request);
    }
    _emitOutbound();
  }

  @override
  Future<void> updateOutboundRequestStatus(
    String pubkey,
    String status,
  ) async {
    final index = _outboundRequests.indexWhere((r) => r.pubkey == pubkey);
    if (index >= 0) {
      final old = _outboundRequests[index];
      _outboundRequests[index] = FollowRequest(
        pubkey: old.pubkey,
        payload: old.payload,
        createdAt: old.createdAt,
        requestTimestamp: old.requestTimestamp,
        status: status,
      );
      _emitOutbound();
    }
  }

  @override
  Future<void> deleteOutboundRequest(String pubkey) async {
    _outboundRequests.removeWhere((r) => r.pubkey == pubkey);
    _emitOutbound();
  }

  // --- Unknown envelope items ---

  final List<UnknownEnvelopeItem> _unknownItems = [];

  @override
  Future<void> saveUnknownEnvelopeItem(UnknownEnvelopeItem item) async {
    _unknownItems.add(item);
  }

  @override
  Future<List<UnknownEnvelopeItem>> getUnknownEnvelopeItemsByType(
    String type,
  ) async =>
      _unknownItems.where((i) => i.type == type).toList();

  // --- Outbound queue ---

  @override
  Future<void> enqueue(String targetPubkey, Uint8List eventBlob) async {
    _queue.add(QueuedEvent(
      id: _nextQueueId++,
      targetPubkey: targetPubkey,
      eventBlob: eventBlob,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  }

  @override
  Future<List<QueuedEvent>> dequeue(String targetPubkey) async =>
      _queue.where((q) => q.targetPubkey == targetPubkey).toList();

  @override
  Future<void> incrementRetry(int id) async {
    final index = _queue.indexWhere((q) => q.id == id);
    if (index >= 0) {
      final old = _queue[index];
      _queue[index] = QueuedEvent(
        id: old.id,
        targetPubkey: old.targetPubkey,
        eventBlob: old.eventBlob,
        createdAt: old.createdAt,
        retryCount: old.retryCount + 1,
      );
    }
  }

  @override
  Future<void> removeFromQueue(int id) async {
    _queue.removeWhere((q) => q.id == id);
  }

  // --- Retention ---

  @override
  Future<int> evictOldEvents(
    int maxAgeSeconds,
    int graceLastViewedSeconds,
  ) async {
    // No-op for mock — retention logic tested in Plan 02/12.
    return 0;
  }

  @override
  Future<int> evictMediaOverLimit(int maxBytes) async {
    return 0;
  }

  @override
  Future<Set<String>> getPinnedMediaHashes() async {
    final pinned = <String>{};
    final ownPubkey = _identity?.pubkey;
    for (final event in _events.values) {
      final pinnedByOwn = ownPubkey != null && event.pubkey == ownPubkey;
      final pinnedBySave = _savedEventIds.contains(event.id);
      if (!pinnedByOwn && !pinnedBySave) continue;
      for (final m in event.media) {
        if (m.hash.isNotEmpty) pinned.add(m.hash);
      }
    }
    return pinned;
  }

  @override
  Future<List<String>> getAllCachedMediaHashes() async =>
      _mediaCache.keys.toList();

  @override
  Future<int> getDatabaseFileSize() async => 0;

  @override
  Future<List<CachedMedia>> evictMediaExcluding(
    int maxBytes,
    Set<String> pinned,
  ) async {
    var totalSize = 0;
    final all = _mediaCache.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    for (final m in all) {
      totalSize += m.size;
    }
    if (totalSize <= maxBytes) return const [];
    final removed = <CachedMedia>[];
    for (final entry in all) {
      if (totalSize <= maxBytes) break;
      if (pinned.contains(entry.hash)) continue;
      _mediaCache.remove(entry.hash);
      totalSize -= entry.size;
      removed.add(entry);
    }
    return removed;
  }

  @override
  Future<List<CachedMedia>> clearCachedMediaExcluding(
    Set<String> pinned,
  ) async {
    final removed = <CachedMedia>[];
    final hashes = _mediaCache.keys.toList();
    for (final hash in hashes) {
      if (pinned.contains(hash)) continue;
      final m = _mediaCache.remove(hash);
      if (m != null) removed.add(m);
    }
    return removed;
  }
}
