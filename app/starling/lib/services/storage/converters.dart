import 'dart:convert';

import 'package:cbor/simple.dart';
import 'package:drift/drift.dart';

import '../../models/models.dart';
import '../types.dart';
import 'database.dart';

// --- Identity ---

Identity identityFromRow(IdentityEntry row) => Identity(
  pubkey: row.pubkey,
  feedKey: row.feedKey,
  feedKeyEpoch: row.feedKeyEpoch,
  feedKeyValidFrom: row.feedKeyValidFrom,
  msgSeqCounter: row.msgSeqCounter,
  recoveryPhrase: row.recoveryPhrase,
  createdAt: row.createdAt,
);

IdentityEntriesCompanion identityToCompanion(Identity identity) =>
    IdentityEntriesCompanion.insert(
      pubkey: identity.pubkey,
      feedKey: identity.feedKey,
      feedKeyEpoch: Value(identity.feedKeyEpoch),
      feedKeyValidFrom: Value(identity.feedKeyValidFrom),
      msgSeqCounter: Value(identity.msgSeqCounter),
      recoveryPhrase: Value(identity.recoveryPhrase),
      createdAt: identity.createdAt,
    );

// --- Feed key history (Plan 13) ---

RetiredFeedKey retiredFeedKeyFromRow(FeedKeyHistoryEntry row) => RetiredFeedKey(
  feedKey: row.feedKey,
  feedKeyEpoch: row.feedKeyEpoch,
  validFrom: row.validFrom,
  validUntil: row.validUntil,
);

RetiredFeedKey retiredFeedKeyFromFollowRow(FollowFeedKeyHistoryEntry row) =>
    RetiredFeedKey(
      feedKey: row.feedKey,
      feedKeyEpoch: row.feedKeyEpoch,
      validFrom: row.validFrom,
      validUntil: row.validUntil,
    );

// --- Pending key distributions (Plan 13) ---

PendingKeyDistribution pendingKeyDistributionFromRow(
  PendingKeyDistributionEntry row,
) => PendingKeyDistribution(
  targetPubkey: row.targetPubkey,
  encryptedFeedKey: row.encryptedFeedKey,
  nonce: row.nonce,
  createdAt: row.createdAt,
);

// --- Follow ---

Follow followFromRow(FollowEntry row) => Follow(
  pubkey: row.pubkey,
  connectionCard: row.connectionCard,
  feedKey: row.feedKey,
  feedKeyEpoch: row.feedKeyEpoch,
  lastSyncedAt: row.lastSyncedAt,
  lastFullSyncAt: row.lastFullSyncAt,
  lastReceivedRotationAt: row.lastReceivedRotationAt,
  lastReceivedCardAt: row.lastReceivedCardAt,
  lastDecryptFailureAt: row.lastDecryptFailureAt,
  status: row.status,
);

FollowEntriesCompanion followToCompanion(Follow follow) =>
    FollowEntriesCompanion.insert(
      pubkey: follow.pubkey,
      connectionCard: follow.connectionCard,
      feedKey: follow.feedKey,
      feedKeyEpoch: Value(follow.feedKeyEpoch),
      lastSyncedAt: Value(follow.lastSyncedAt),
      lastFullSyncAt: Value(follow.lastFullSyncAt),
      lastReceivedRotationAt: Value(follow.lastReceivedRotationAt),
      lastReceivedCardAt: Value(follow.lastReceivedCardAt),
      lastDecryptFailureAt: Value(follow.lastDecryptFailureAt),
      status: Value(follow.status),
    );

// --- Paired relay + card distributions (Plan 15) ---

PairedRelay pairedRelayFromRow(PairedRelayEntry row) => PairedRelay(
  relayId: row.relayId,
  relayOnion: row.relayOnion,
  pairedAt: row.pairedAt,
  backfillComplete: row.relayBackfillComplete == 1,
  relayPruneBefore: row.relayPruneBefore,
  lastPushAt: row.lastPushAt,
  lastError: row.lastError,
);

RelayFanoutState relayFanoutStateFromRow(RelayFanoutStateEntry? row) =>
    row == null
    ? const RelayFanoutState()
    : RelayFanoutState(
        pendingCardFanout: row.pendingCardFanout == 1,
        pendingUnpairOnion: row.pendingUnpairOnion,
        unpairNotifyAttempts: row.unpairNotifyAttempts,
      );

PendingCardDistribution pendingCardDistributionFromRow(
  PendingCardDistributionEntry row,
) => PendingCardDistribution(
  targetPubkey: row.targetPubkey,
  encryptedCard: row.encryptedCard,
  nonce: row.nonce,
  createdAt: row.createdAt,
);

// --- Event ---

Event eventFromRow(EventEntry row) => Event(
  version: row.version,
  id: row.id,
  pubkey: row.pubkey,
  createdAt: row.createdAt,
  kind: EventKind.fromValue(row.kind),
  ref: row.refId,
  content: row.content,
  media: _decodeMediaRefs(row.mediaRefs),
  extensions: _decodeExtensions(row.extensions),
  sig: row.sig,
  msgSeq: row.msgSeq,
);

EventEntriesCompanion eventToCompanion(
  Event event, {
  required bool isOwn,
  required int fetchedAt,
  Uint8List? encryptedPayload,
}) => EventEntriesCompanion.insert(
  id: event.id,
  pubkey: event.pubkey,
  createdAt: event.createdAt,
  kind: event.kind.value,
  refId: Value(event.ref),
  content: event.content,
  mediaRefs: Value(_encodeMediaRefs(event.media)),
  sig: event.sig,
  isOwn: Value(isOwn ? 1 : 0),
  fetchedAt: fetchedAt,
  version: Value(event.version),
  extensions: Value(_encodeExtensions(event.extensions)),
  msgSeq: Value(event.msgSeq),
  encryptedPayload: Value(encryptedPayload),
);

String? _encodeMediaRefs(List<MediaRef> media) {
  if (media.isEmpty) return null;
  return jsonEncode(media.map((m) => m.toMap()).toList());
}

List<MediaRef> _decodeMediaRefs(String? json) {
  if (json == null || json.isEmpty) return [];
  final list = jsonDecode(json) as List<dynamic>;
  return list
      .map((item) => MediaRef.fromMap(item as Map<dynamic, dynamic>))
      .toList();
}

// --- CachedMedia ---

CachedMedia cachedMediaFromRow(MediaCacheEntry row) => CachedMedia(
  hash: row.hash,
  path: row.path,
  size: row.size,
  lastAccessed: row.lastAccessed,
);

MediaCacheEntriesCompanion cachedMediaToCompanion(CachedMedia media) =>
    MediaCacheEntriesCompanion.insert(
      hash: media.hash,
      path: media.path,
      size: media.size,
      lastAccessed: media.lastAccessed,
    );

// --- FollowRequest ---

FollowRequest inboundRequestFromRow(InboundFollowRequestEntry row) =>
    FollowRequest(
      pubkey: row.pubkey,
      payload: row.encryptedEndpoints,
      createdAt: row.createdAt,
      requestTimestamp: row.requestTimestamp,
      status: row.status,
    );

FollowRequest outboundRequestFromRow(OutboundFollowRequestEntry row) =>
    FollowRequest(
      pubkey: row.pubkey,
      payload: base64.decode(row.connectionCard),
      createdAt: row.createdAt,
      requestTimestamp: row.createdAt,
      status: row.status,
    );

// --- QueuedEvent ---

QueuedEvent queuedEventFromRow(OutboundQueueEntry row) => QueuedEvent(
  id: row.id,
  targetPubkey: row.targetPubkey,
  eventBlob: row.eventBlob,
  createdAt: row.createdAt,
  retryCount: row.retryCount,
  itemType: row.itemType,
);

// --- Chatrooms (Plan 17) ---

Room roomFromRow(RoomEntry row) => Room(
  id: row.id,
  name: row.name,
  creatorPubkey: row.creatorPubkey,
  createdAt: row.createdAt,
  lastActivityAt: row.lastActivityAt,
  roomKey: row.roomKey,
  roomKeyEpoch: row.roomKeyEpoch,
  roomKeyValidFrom: row.roomKeyValidFrom,
  roomMsgSeqCounter: row.roomMsgSeqCounter,
  membershipEpoch: row.membershipEpoch,
  isMember: row.isMember == 1,
  lastReadAt: row.lastReadAt,
);

RoomMember roomMemberFromRow(RoomMemberEntry row) => RoomMember(
  roomId: row.roomId,
  pubkey: row.pubkey,
  displayName: row.displayName,
  addedAt: row.addedAt,
  removedAt: row.removedAt,
  role: row.role,
);

RetiredRoomKey retiredRoomKeyFromRow(RoomKeyHistoryEntry row) => RetiredRoomKey(
  roomKey: row.roomKey,
  epoch: row.epoch,
  validFrom: row.validFrom,
  validUntil: row.validUntil,
);

// --- Extensions ---

Uint8List? _encodeExtensions(Map<String, Uint8List> extensions) {
  if (extensions.isEmpty) return null;
  return Uint8List.fromList(cbor.encode(extensions));
}

Map<String, Uint8List> _decodeExtensions(Uint8List? blob) {
  if (blob == null || blob.isEmpty) return const {};
  final decoded = cbor.decode(blob);
  if (decoded is Map) {
    return Map.unmodifiable(
      decoded.map((k, v) => MapEntry(k.toString(), _toUint8List(v))),
    );
  }
  return const {};
}

Uint8List _toUint8List(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List) return Uint8List.fromList(value.cast<int>());
  throw ArgumentError('Expected bytes, got ${value.runtimeType}');
}
