import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../clock.dart';
import '../storage_service.dart';
import '../types.dart';
import 'converters.dart';
import 'database.dart';

class DriftStorageService implements StorageService {
  DriftStorageService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  // --- Identity ---

  @override
  Future<Identity?> getIdentity() async {
    final row = await _db.identityDao.getIdentity();
    return row == null ? null : identityFromRow(row);
  }

  @override
  Future<void> saveIdentity(Identity identity) =>
      _db.identityDao.upsertIdentity(identityToCompanion(identity));

  // --- Follows ---

  @override
  Future<List<Follow>> getFollows() async {
    final rows = await _db.followsDao.getActiveFollows();
    return rows.map(followFromRow).toList();
  }

  @override
  Stream<List<Follow>> watchFollows() => _db.followsDao
      .watchActiveFollows()
      .map((rows) => rows.map(followFromRow).toList());

  @override
  Future<Follow?> getFollow(String pubkey) async {
    final row = await _db.followsDao.getFollow(pubkey);
    return row == null ? null : followFromRow(row);
  }

  @override
  Future<void> saveFollow(Follow follow) =>
      _db.followsDao.upsertFollow(followToCompanion(follow));

  @override
  Future<void> removeFollow(String pubkey) =>
      _db.followsDao.removeFollow(pubkey);

  @override
  Future<void> updateLastSynced(String pubkey, int timestamp) =>
      _db.followsDao.updateLastSynced(pubkey, timestamp);

  @override
  Future<void> setLastDecryptFailureAt(String pubkey, int? timestamp) =>
      _db.followsDao.setLastDecryptFailureAt(pubkey, timestamp);

  @override
  Future<void> clearLastDecryptFailureIfSet(String pubkey) =>
      _db.followsDao.clearLastDecryptFailureIfSet(pubkey);

  // --- Events ---

  @override
  Future<List<Event>> getEvents({
    String? pubkey,
    int? since,
    int? until,
    int? limit,
  }) async {
    final rows = await _db.eventsDao.getEvents(
      pubkey: pubkey,
      since: since,
      until: until,
      limit: limit,
    );
    return rows.map(eventFromRow).toList();
  }

  @override
  Future<Event?> getEvent(String id) async {
    final row = await _db.eventsDao.getEvent(id);
    return row == null ? null : eventFromRow(row);
  }

  @override
  Future<void> saveEvent(Event event) async {
    final identity = await _db.identityDao.getIdentity();
    final isOwn = identity != null && identity.pubkey == event.pubkey;
    await _db.eventsDao.upsertEvent(
      eventToCompanion(event, isOwn: isOwn, fetchedAt: _clock.nowUnixSeconds()),
    );
  }

  @override
  Future<void> saveOwnEventWithEncrypted(
    Event event,
    Uint8List encryptedPayload,
  ) async {
    await _db.eventsDao.upsertEvent(
      eventToCompanion(
        event,
        isOwn: true,
        fetchedAt: _clock.nowUnixSeconds(),
        encryptedPayload: encryptedPayload,
      ),
    );
  }

  @override
  Future<Uint8List?> getEncryptedPayload(String id) =>
      _db.eventsDao.getEncryptedPayload(id);

  @override
  Future<void> deleteEvent(String id) => _db.eventsDao.deleteEvent(id);

  @override
  Future<List<Event>> getFeedEvents({int? since, int? limit}) async {
    final rows =
        await _db.eventsDao.getFeedEvents(since: since, limit: limit);
    return rows.map(eventFromRow).toList();
  }

  @override
  Future<List<Event>> getProfilePosts(String pubkey, {int? limit}) async {
    final rows = await _db.eventsDao.getProfilePosts(pubkey, limit: limit);
    return rows.map(eventFromRow).toList();
  }

  @override
  Future<List<Event>> getEventsByRef(String refId, {EventKind? kind}) async {
    final rows =
        await _db.eventsDao.getEventsByRef(refId, kind: kind?.value);
    return rows.map(eventFromRow).toList();
  }

  @override
  Future<List<Event>> getOwnAndIncomingRefs(
    String ownerPubkey, {
    int? since,
    int? limit,
  }) async {
    final rows = await _db.eventsDao.getOwnAndIncomingRefs(
      ownerPubkey,
      since: since,
      limit: limit,
    );
    return rows.map(eventFromRow).toList();
  }

  @override
  Future<bool> isEventSaved(String id) =>
      _db.eventsDao.isEventSaved(id);

  @override
  Future<void> setEventSaved(String id, bool saved) =>
      _db.eventsDao.setEventSaved(id, saved);

  @override
  Future<void> setEventLastViewed(String id, int timestamp) =>
      _db.eventsDao.setLastViewed(id, timestamp);

  // --- Media cache ---

  @override
  Future<CachedMedia?> getMedia(String hash) async {
    final row = await _db.mediaCacheDao.getMedia(hash);
    return row == null ? null : cachedMediaFromRow(row);
  }

  @override
  Future<void> saveMedia(CachedMedia media) =>
      _db.mediaCacheDao.upsertMedia(cachedMediaToCompanion(media));

  @override
  Future<void> deleteMedia(String hash) =>
      _db.mediaCacheDao.deleteMedia(hash);

  @override
  Future<int> getMediaCacheSize() => _db.mediaCacheDao.getTotalSize();

  @override
  Future<void> evictMedia(int targetSize) =>
      _db.mediaCacheDao.evictToSize(targetSize);

  // --- Followers (Plan 13) ---

  @override
  Future<List<String>> getAcceptedFollowerPubkeys() async {
    final rows =
        await _db.followRequestsDao.getInboundByStatus('accepted');
    return rows.map((r) => r.pubkey).toList();
  }

  @override
  Future<bool> isAcceptedFollower(String pubkey) async {
    final row = await _db.followRequestsDao.getInbound(pubkey);
    return row != null && row.status == 'accepted';
  }

  @override
  Future<void> removeAcceptedFollower(String pubkey) =>
      _db.followRequestsDao.deleteInbound(pubkey);

  // --- Feed key history (Plan 13) ---

  @override
  Future<void> appendFeedKeyHistory({
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  }) =>
      _db.keyRotationDao.appendFeedKeyHistory(
        FeedKeyHistoryEntriesCompanion.insert(
          feedKey: feedKey,
          feedKeyEpoch: Value(feedKeyEpoch),
          validFrom: validFrom,
          validUntil: validUntil,
        ),
      );

  @override
  Future<RetiredFeedKey?> retiredFeedKeyAt(int timestamp) async {
    final row = await _db.keyRotationDao.feedKeyAt(timestamp);
    return row == null ? null : retiredFeedKeyFromRow(row);
  }

  @override
  Future<List<RetiredFeedKey>> getFeedKeyHistory() async {
    final rows = await _db.keyRotationDao.getFeedKeyHistory();
    return rows.map(retiredFeedKeyFromRow).toList();
  }

  // --- Per-follow feed-key history (MegOLM archive) ---

  @override
  Future<void> appendFollowFeedKeyHistory({
    required String followPubkey,
    required Uint8List feedKey,
    required int feedKeyEpoch,
    required int validFrom,
    required int validUntil,
  }) =>
      _db.keyRotationDao.appendFollowFeedKeyHistory(
        FollowFeedKeyHistoryEntriesCompanion.insert(
          followPubkey: followPubkey,
          feedKey: feedKey,
          feedKeyEpoch: Value(feedKeyEpoch),
          validFrom: validFrom,
          validUntil: validUntil,
        ),
      );

  @override
  Future<List<RetiredFeedKey>> getFollowFeedKeyHistory(
    String followPubkey,
  ) async {
    final rows =
        await _db.keyRotationDao.getFollowFeedKeyHistory(followPubkey);
    return rows.map(retiredFeedKeyFromFollowRow).toList();
  }

  // --- Pending key distributions (Plan 13) ---

  @override
  Future<void> addPendingKeyDistribution({
    required String targetPubkey,
    required Uint8List encryptedFeedKey,
    required Uint8List nonce,
    required int createdAt,
  }) =>
      _db.keyRotationDao.addPendingDistribution(
        PendingKeyDistributionEntriesCompanion.insert(
          targetPubkey: targetPubkey,
          encryptedFeedKey: encryptedFeedKey,
          nonce: nonce,
          createdAt: createdAt,
        ),
      );

  @override
  Future<PendingKeyDistribution?> latestPendingDistributionFor(
    String targetPubkey,
  ) async {
    final row = await _db.keyRotationDao.latestPendingFor(targetPubkey);
    return row == null ? null : pendingKeyDistributionFromRow(row);
  }

  @override
  Future<void> markDistributionsDelivered(
    String targetPubkey,
    int upTo,
  ) =>
      _db.keyRotationDao.markDistributionsDelivered(targetPubkey, upTo);

  @override
  Future<void> clearPendingDistributionsFor(String targetPubkey) =>
      _db.keyRotationDao.clearPendingDistributionsFor(targetPubkey);

  // --- Paired relay + card distributions (Plan 15) ---

  @override
  Future<PairedRelay?> getPairedRelay() async {
    final row = await _db.pairedRelayDao.getPairedRelay();
    return row == null ? null : pairedRelayFromRow(row);
  }

  @override
  Future<void> setPairedRelay({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
  }) =>
      _db.pairedRelayDao.setPairedRelay(
        relayId: relayId,
        relayOnion: relayOnion,
        pairedAt: pairedAt,
      );

  @override
  Future<void> markRelayBackfillComplete(String relayId) =>
      _db.pairedRelayDao.markBackfillComplete(relayId);

  @override
  Future<void> clearPairedRelay() => _db.pairedRelayDao.clearPairedRelay();

  @override
  Future<void> queueCardDistribution({
    required String targetPubkey,
    required Uint8List cardCbor,
    required Uint8List sig,
    required int createdAt,
  }) =>
      _db.pairedRelayDao.queueCardDistribution(
        PendingCardDistributionEntriesCompanion.insert(
          targetPubkey: targetPubkey,
          cardCbor: cardCbor,
          sig: sig,
          createdAt: createdAt,
        ),
      );

  @override
  Future<PendingCardDistribution?> latestPendingCardFor(
    String targetPubkey,
  ) async {
    final row = await _db.pairedRelayDao.latestPendingCardFor(targetPubkey);
    return row == null ? null : pendingCardDistributionFromRow(row);
  }

  @override
  Future<void> markCardDistributionsDelivered(
    String targetPubkey,
    int upTo,
  ) =>
      _db.pairedRelayDao.markCardDistributionsDelivered(targetPubkey, upTo);

  @override
  Future<void> clearCardDistributionsFor(String targetPubkey) =>
      _db.pairedRelayDao.clearCardDistributionsFor(targetPubkey);

  // --- Follow requests ---

  @override
  Future<List<FollowRequest>> getInboundRequests() async {
    final rows = await _db.followRequestsDao.getInboundPending();
    return rows.map(inboundRequestFromRow).toList();
  }

  @override
  Stream<List<FollowRequest>> watchInboundRequests() => _db
      .followRequestsDao
      .watchInboundPending()
      .map((rows) => rows.map(inboundRequestFromRow).toList());

  @override
  Stream<List<FollowRequest>> watchInboundFollowers() => _db
      .followRequestsDao
      .watchInboundActioned()
      .map((rows) => rows.map(inboundRequestFromRow).toList());

  @override
  Future<List<FollowRequest>> getInboundRequestsByStatus(String status) async {
    final rows = await _db.followRequestsDao.getInboundByStatus(status);
    return rows.map(inboundRequestFromRow).toList();
  }

  @override
  Future<FollowRequest?> getInboundRequest(String pubkey) async {
    final row = await _db.followRequestsDao.getInbound(pubkey);
    return row == null ? null : inboundRequestFromRow(row);
  }

  @override
  Future<void> saveInboundRequest(FollowRequest request) =>
      _db.followRequestsDao.upsertInbound(
        InboundFollowRequestEntriesCompanion.insert(
          pubkey: request.pubkey,
          encryptedEndpoints: request.payload,
          createdAt: request.createdAt,
          requestTimestamp: Value(request.requestTimestamp),
          status: Value(request.status),
        ),
      );

  @override
  Future<void> updateInboundRequestStatus(String pubkey, String status) =>
      _db.followRequestsDao.updateInboundStatus(pubkey, status);

  @override
  Future<void> deleteInboundRequest(String pubkey) =>
      _db.followRequestsDao.deleteInbound(pubkey);

  @override
  Future<List<FollowRequest>> getOutboundRequests() async {
    final rows = await _db.followRequestsDao.getOutbound();
    return rows.map(outboundRequestFromRow).toList();
  }

  @override
  Stream<List<FollowRequest>> watchOutboundRequests() => _db
      .followRequestsDao
      .watchOutbound()
      .map((rows) => rows.map(outboundRequestFromRow).toList());

  @override
  Future<FollowRequest?> getOutboundRequest(String pubkey) async {
    final row = await _db.followRequestsDao.getOutboundFor(pubkey);
    return row == null ? null : outboundRequestFromRow(row);
  }

  @override
  Future<void> saveOutboundRequest(FollowRequest request) =>
      _db.followRequestsDao.upsertOutbound(
        OutboundFollowRequestEntriesCompanion.insert(
          pubkey: request.pubkey,
          // Payload is raw CBOR; base64 keeps it ASCII-safe in the text
          // column. utf8.decode would crash on the first non-ASCII byte
          // (CBOR map headers like 0xa3 are UTF-8 continuation bytes).
          connectionCard: base64.encode(request.payload),
          createdAt: request.createdAt,
          status: Value(request.status),
        ),
      );

  @override
  Future<void> updateOutboundRequestStatus(String pubkey, String status) =>
      _db.followRequestsDao.updateOutboundStatus(pubkey, status);

  @override
  Future<void> deleteOutboundRequest(String pubkey) =>
      _db.followRequestsDao.deleteOutbound(pubkey);

  // --- Unknown envelope items ---

  @override
  Future<void> saveUnknownEnvelopeItem(UnknownEnvelopeItem item) =>
      _db.unknownItemsDao.insert(
        UnknownEnvelopeItemEntriesCompanion.insert(
          sourcePubkey: item.sourcePubkey,
          envelopeVersion: item.envelopeVersion,
          type: item.type,
          payload: item.payload,
          extensions: Value(item.extensions),
          receivedAt: item.receivedAt,
        ),
      );

  @override
  Future<List<UnknownEnvelopeItem>> getUnknownEnvelopeItemsByType(
    String type,
  ) async {
    final rows = await _db.unknownItemsDao.getByType(type);
    return rows
        .map((r) => UnknownEnvelopeItem(
              sourcePubkey: r.sourcePubkey,
              envelopeVersion: r.envelopeVersion,
              type: r.type,
              payload: r.payload,
              extensions: r.extensions,
              receivedAt: r.receivedAt,
            ))
        .toList();
  }

  // --- Outbound queue ---

  @override
  Future<void> enqueue(String targetPubkey, Uint8List eventBlob) =>
      _db.outboundQueueDao.enqueue(
        OutboundQueueEntriesCompanion.insert(
          targetPubkey: targetPubkey,
          eventBlob: eventBlob,
          createdAt: _clock.nowUnixSeconds(),
        ),
      );

  @override
  Future<List<QueuedEvent>> dequeue(String targetPubkey) async {
    final rows = await _db.outboundQueueDao.dequeue(targetPubkey);
    return rows.map(queuedEventFromRow).toList();
  }

  @override
  Future<void> incrementRetry(int id) =>
      _db.outboundQueueDao.incrementRetry(id);

  @override
  Future<void> removeFromQueue(int id) =>
      _db.outboundQueueDao.removeFromQueue(id);

  // --- Retention ---

  @override
  Future<int> evictOldEvents(
    int maxAgeSeconds,
    int graceLastViewedSeconds,
  ) =>
      _db.eventsDao.evictOldEvents(
        maxAgeSeconds,
        graceLastViewedSeconds,
        now: _clock.nowUnixSeconds(),
      );

  @override
  Future<int> evictMediaOverLimit(int maxBytes) =>
      _db.mediaCacheDao.evictOverLimit(maxBytes);

  @override
  Future<Set<String>> getPinnedMediaHashes() async {
    final jsonStrings = await _db.eventsDao.getPinnedMediaRefsJson();
    final pinned = <String>{};
    for (final raw in jsonStrings) {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<dynamic, dynamic>;
        final hash = map['hash'];
        if (hash is String && hash.isNotEmpty) {
          pinned.add(hash);
        }
      }
    }
    return pinned;
  }

  @override
  Future<List<String>> getAllCachedMediaHashes() =>
      _db.mediaCacheDao.getAllHashes();

  @override
  Future<int> getDatabaseFileSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'starling.db'));
      if (!file.existsSync()) return 0;
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<List<CachedMedia>> evictMediaExcluding(
    int maxBytes,
    Set<String> pinned,
  ) async {
    final removed =
        await _db.mediaCacheDao.evictOverLimitExcluding(maxBytes, pinned);
    return removed.map(cachedMediaFromRow).toList();
  }

  @override
  Future<List<CachedMedia>> clearCachedMediaExcluding(
    Set<String> pinned,
  ) async {
    final removed = await _db.mediaCacheDao.deleteAllExcluding(pinned);
    return removed.map(cachedMediaFromRow).toList();
  }
}
