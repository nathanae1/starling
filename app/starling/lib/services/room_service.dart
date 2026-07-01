import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import '../sync/room_delivery.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/publish_lock.dart';
import 'crypto_service.dart';
import 'room_key_rotation_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Newest-K room messages replayed to a newly-added member (bounded backfill;
/// full backfill awaits Phase H room-scoped pull).
const int kRoomHistoryReplayLimit = 50;

/// Durable chatroom lifecycle (Plan 17): create, membership admin, leave.
/// Text messaging is [RoomMessageService]; the live call is [RoomManager].
/// All mutating paths hold the shared [PublishLock] so a room-key rotation or
/// membership change can't interleave with message authoring on the same
/// per-room msg_seq chain.
abstract class RoomService {
  /// Create a durable chatroom named [name] with [memberPubkeys] (restricted
  /// to mutual follows). Mints the room key, authors `roomCreate` +
  /// `roomMembership`, seals the key to members and fans the genesis out.
  /// Returns the roomId (= the genesis event id).
  Future<String> createRoom({
    required String name,
    required List<String> memberPubkeys,
  });

  /// Creator-only: add [pubkey] (a mutual follow). Seals the CURRENT key (so
  /// the newcomer reads history), authors a fresh `roomMembership`, and
  /// replays the genesis + newest-K messages. No key rotation on add.
  Future<void> addMember(String roomId, String pubkey);

  /// Creator-only: remove [pubkey] and rotate the room key (backward
  /// secrecy). Delegates to [RoomKeyRotationService].
  Future<void> removeMember(String roomId, String pubkey);

  /// Local leave: stop being a member and unpin this room's messages so
  /// retention can eventually evict the left, idle room.
  Future<void> leaveRoom(String roomId);

  /// Author a durable `roomCallStarted` (kind 103) naming [callId] and fan it
  /// out to members, so offline members see the call on next sync. No-op if
  /// we're not a member of [roomId].
  Future<void> announceCall({required String roomId, required String callId});
}

class DefaultRoomService implements RoomService {
  DefaultRoomService({
    required CryptoService crypto,
    required ContentKeyService contentKey,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required RoomKeyRotationService rotationService,
    required PublishLock publishLock,
  }) : _crypto = crypto,
       _contentKey = contentKey,
       _storage = storage,
       _clock = clock,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _rotation = rotationService,
       _publishLock = publishLock;

  final CryptoService _crypto;
  final ContentKeyService _contentKey;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final RoomKeyRotationService _rotation;
  final PublishLock _publishLock;

  @override
  Future<String> createRoom({
    required String name,
    required List<String> memberPubkeys,
  }) => _publishLock.synchronized(() async {
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) {
      throw StateError('createRoom called before identity is loaded');
    }
    final now = _clock.nowUnixSeconds();
    final roomKey = _crypto.randomBytes(32);

    // Restrict members to mutual follows (defensive; UI already filters).
    final members = <String>[];
    for (final pk in memberPubkeys) {
      if (pk == identity.pubkey) continue;
      if (await _isMutualFollow(pk)) members.add(pk);
    }

    // seq 0 → roomCreate; its event id becomes the roomId.
    final createResult = _contentKey.signAndEncryptForRoom(
      _unsigned(
        pubkey: identity.pubkey,
        createdAt: now,
        kind: EventKind.roomCreate,
        content: encodeRoomCreateContent(
          RoomCreateContent(
            name: name,
            creatorPubkey: identity.pubkey,
            createdAt: now,
          ),
        ),
      ),
      roomKey: roomKey,
      roomEpoch: 0,
      roomMsgSeq: 0,
    );
    final roomId = createResult.signed.id;
    await _storage.saveOwnEventWithEncrypted(
      createResult.signed,
      createResult.encrypted.toBytes(),
    );

    // seq 1 → initial roomMembership (roster = self + members).
    final roster = [identity.pubkey, ...members];
    final memResult = _contentKey.signAndEncryptForRoom(
      _unsigned(
        pubkey: identity.pubkey,
        createdAt: now,
        kind: EventKind.roomMembership,
        ref: roomId,
        content: encodeRoomMembershipContent(
          RoomMembershipContent(
            members: roster,
            membershipEpoch: 1,
            roomKeyEpoch: 0,
          ),
        ),
      ),
      roomKey: roomKey,
      roomEpoch: 0,
      roomMsgSeq: 1,
    );
    await _storage.saveOwnEventWithEncrypted(
      memResult.signed,
      memResult.encrypted.toBytes(),
    );

    // Persist the room row (next seq = 2) and roster.
    await _storage.saveRoom(
      Room(
        id: roomId,
        name: name,
        creatorPubkey: identity.pubkey,
        createdAt: now,
        lastActivityAt: now,
        roomKey: roomKey,
        roomKeyEpoch: 0,
        roomKeyValidFrom: now,
        roomMsgSeqCounter: 2,
        membershipEpoch: 1,
        isMember: true,
        lastReadAt: now,
      ),
    );
    await _storage.saveRoomMember(
      RoomMember(
        roomId: roomId,
        pubkey: identity.pubkey,
        addedAt: now,
        role: 'creator',
      ),
    );
    for (final pk in members) {
      await _storage.saveRoomMember(
        RoomMember(roomId: roomId, pubkey: pk, addedAt: now),
      );
    }

    // Seal the key + fan the genesis (roomCreate, roomMembership) out.
    await sealRoomKeyToMembers(
      crypto: _crypto,
      storage: _storage,
      roomId: roomId,
      senderPubkey: identity.pubkey,
      senderSecretKey: secretKey,
      roomKey: roomKey,
      epoch: 0,
      validFrom: now,
      recipientPubkeys: members,
    );
    for (final pk in members) {
      await fanOutRoomEvent(
        _storage,
        pk,
        roomId,
        createResult.encrypted.toBytes(),
      );
      await fanOutRoomEvent(
        _storage,
        pk,
        roomId,
        memResult.encrypted.toBytes(),
      );
    }
    return roomId;
  });

  @override
  Future<void> addMember(String roomId, String pubkey) =>
      _publishLock.synchronized(() async {
        final identity = await _identityLookup();
        final secretKey = await _ownSecretKeyLookup();
        if (identity == null || secretKey == null) {
          throw StateError('addMember called before identity is loaded');
        }
        final room = await _storage.getRoom(roomId);
        if (room == null) throw StateError('addMember: unknown room $roomId');
        if (room.creatorPubkey != identity.pubkey) {
          throw StateError('addMember: creator-only in v1');
        }
        if (pubkey == identity.pubkey) return;
        if (!await _isMutualFollow(pubkey)) {
          throw StateError('addMember: $pubkey is not a mutual follow');
        }
        final now = _clock.nowUnixSeconds();

        // Record the new member, then compute the fresh roster + membership.
        await _storage.saveRoomMember(
          RoomMember(roomId: roomId, pubkey: pubkey, addedAt: now),
        );
        final roster = (await _storage.getRoomMembers(roomId))
            .where((m) => m.isActive)
            .map((m) => m.pubkey)
            .toList(growable: false);
        final newMembershipEpoch = room.membershipEpoch + 1;
        final seq = room.roomMsgSeqCounter;
        final memResult = _contentKey.signAndEncryptForRoom(
          _unsigned(
            pubkey: identity.pubkey,
            createdAt: now,
            kind: EventKind.roomMembership,
            ref: roomId,
            content: encodeRoomMembershipContent(
              RoomMembershipContent(
                members: roster,
                membershipEpoch: newMembershipEpoch,
                roomKeyEpoch: room.roomKeyEpoch,
              ),
            ),
          ),
          roomKey: room.roomKey,
          roomEpoch: room.roomKeyEpoch,
          roomMsgSeq: seq,
        );
        await _storage.saveOwnEventWithEncrypted(
          memResult.signed,
          memResult.encrypted.toBytes(),
        );
        await _storage.saveRoom(
          room.copyWith(
            roomMsgSeqCounter: seq + 1,
            membershipEpoch: newMembershipEpoch,
            lastActivityAt: now,
          ),
        );

        // Seal the CURRENT key to the newcomer (so they read history).
        await sealRoomKeyToMembers(
          crypto: _crypto,
          storage: _storage,
          roomId: roomId,
          senderPubkey: identity.pubkey,
          senderSecretKey: secretKey,
          roomKey: room.roomKey,
          epoch: room.roomKeyEpoch,
          validFrom: room.roomKeyValidFrom,
          recipientPubkeys: [pubkey],
        );

        // Fan the new roster to everyone; replay history to the newcomer.
        for (final p in roster.where((p) => p != identity.pubkey)) {
          await fanOutRoomEvent(
            _storage,
            p,
            roomId,
            memResult.encrypted.toBytes(),
          );
        }
        await _replayHistoryTo(pubkey, roomId);
      });

  @override
  Future<void> removeMember(String roomId, String pubkey) =>
      _rotation.rotate(roomId: roomId, removedPubkey: pubkey);

  @override
  Future<void> leaveRoom(String roomId) => _publishLock.synchronized(() async {
    final room = await _storage.getRoom(roomId);
    if (room == null) return;
    await _storage.saveRoom(room.copyWith(isMember: false));
    // Unpin the room's messages so retention can prune the left, idle room.
    final events = await _storage.getEventsByRef(roomId);
    for (final e in events) {
      await _storage.setEventSaved(e.id, false);
    }
  });

  @override
  Future<void> announceCall({
    required String roomId,
    required String callId,
  }) => _publishLock.synchronized(() async {
    final identity = await _identityLookup();
    if (identity == null) {
      throw StateError('announceCall called before identity is loaded');
    }
    final room = await _storage.getRoom(roomId);
    if (room == null || !room.isMember) return;
    final now = _clock.nowUnixSeconds();
    final seq = room.roomMsgSeqCounter;
    final result = _contentKey.signAndEncryptForRoom(
      _unsigned(
        pubkey: identity.pubkey,
        createdAt: now,
        kind: EventKind.roomCallStarted,
        ref: roomId,
        content: encodeRoomCallStartedContent(
          RoomCallStartedContent(
            callId: callId,
            starterPubkey: identity.pubkey,
          ),
        ),
      ),
      roomKey: room.roomKey,
      roomEpoch: room.roomKeyEpoch,
      roomMsgSeq: seq,
    );
    await _storage.saveOwnEventWithEncrypted(
      result.signed,
      result.encrypted.toBytes(),
    );
    await _storage.saveRoom(
      room.copyWith(roomMsgSeqCounter: seq + 1, lastActivityAt: now),
    );
    final members = await _storage.getRoomMembers(roomId);
    for (final m in members) {
      if (!m.isActive || m.pubkey == identity.pubkey) continue;
      await fanOutRoomEvent(
        _storage,
        m.pubkey,
        roomId,
        result.encrypted.toBytes(),
      );
    }
  });

  /// Replay the genesis + newest-K messages to [pubkey]. Only events whose
  /// wire bytes we still hold are replayable (own-authored always; received
  /// once ingest persists their payload) — bounded, per the v1 design.
  Future<void> _replayHistoryTo(String pubkey, String roomId) async {
    final createPayload = await _storage.getEncryptedPayload(roomId);
    if (createPayload != null) {
      await fanOutRoomEvent(_storage, pubkey, roomId, createPayload);
    }
    final msgs = await _storage.getEventsByRef(
      roomId,
      kind: EventKind.roomMessage,
    );
    final recent = msgs.length <= kRoomHistoryReplayLimit
        ? msgs
        : msgs.sublist(msgs.length - kRoomHistoryReplayLimit);
    for (final msg in recent) {
      final payload = await _storage.getEncryptedPayload(msg.id);
      if (payload != null) {
        await fanOutRoomEvent(_storage, pubkey, roomId, payload);
      }
    }
  }

  /// Membership gate: active outbound follow AND accepted inbound follower —
  /// the same "mutual follow" set the voice invite path uses.
  Future<bool> _isMutualFollow(String pubkey) async {
    final follow = await _storage.getFollow(pubkey);
    if (follow == null || follow.status != 'active') return false;
    return _storage.isAcceptedFollower(pubkey);
  }

  Event _unsigned({
    required String pubkey,
    required int createdAt,
    required EventKind kind,
    String? ref,
    required Uint8List content,
  }) => Event(
    version: kStarlingProtocolVersion,
    id: '',
    pubkey: pubkey,
    createdAt: createdAt,
    kind: kind,
    ref: ref,
    content: content,
    sig: Uint8List(0),
  );
}
