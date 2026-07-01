import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import '../sync/room_delivery.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/publish_lock.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Rotates a room key when the creator removes a member (Plan 17). Mirrors
/// [KeyRotationService]: archive the current key with its active window, mint
/// a fresh key at the next epoch, then re-seal it to every *remaining* member
/// and author a new `roomMembership`. The removed member keeps the old key
/// (reads history) but cannot derive the new chain — backward secrecy.
abstract class RoomKeyRotationService {
  Future<void> rotate({required String roomId, required String removedPubkey});
}

class DefaultRoomKeyRotationService implements RoomKeyRotationService {
  DefaultRoomKeyRotationService({
    required CryptoService crypto,
    required ContentKeyService contentKey,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required PublishLock publishLock,
  }) : _crypto = crypto,
       _contentKey = contentKey,
       _storage = storage,
       _clock = clock,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _publishLock = publishLock;

  final CryptoService _crypto;
  final ContentKeyService _contentKey;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final PublishLock _publishLock;

  @override
  Future<void> rotate({
    required String roomId,
    required String removedPubkey,
  }) => _publishLock.synchronized(() => _rotateLocked(roomId, removedPubkey));

  Future<void> _rotateLocked(String roomId, String removedPubkey) async {
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) {
      throw StateError('cannot rotate room key: identity not loaded');
    }
    final room = await _storage.getRoom(roomId);
    if (room == null) return;
    if (room.creatorPubkey != identity.pubkey) {
      throw StateError('rotate: creator-only in v1');
    }

    final now = _clock.nowUnixSeconds();

    // 1. Retire the current key with its active window.
    await _storage.appendRoomKeyHistory(
      roomId,
      roomKey: room.roomKey,
      epoch: room.roomKeyEpoch,
      validFrom: room.roomKeyValidFrom == 0
          ? room.createdAt
          : room.roomKeyValidFrom,
      validUntil: now,
    );

    // 2. Stamp the removal so the roster excludes X.
    await _storage.setRoomMemberRemoved(roomId, removedPubkey, now);

    // 3. Mint the fresh key at the next epoch; msg_seq restarts at 0.
    final newKey = _crypto.randomBytes(32);
    final newEpoch = room.roomKeyEpoch + 1;
    final newMembershipEpoch = room.membershipEpoch + 1;

    final roster = (await _storage.getRoomMembers(roomId))
        .where((m) => m.isActive)
        .map((m) => m.pubkey)
        .toList(growable: false);

    // seq 0 under the NEW key → the post-rotation roomMembership (roster
    // without X, pinned to the new key epoch).
    final memUnsigned = Event(
      version: kStarlingProtocolVersion,
      id: '',
      pubkey: identity.pubkey,
      createdAt: now,
      kind: EventKind.roomMembership,
      ref: roomId,
      content: encodeRoomMembershipContent(
        RoomMembershipContent(
          members: roster,
          membershipEpoch: newMembershipEpoch,
          roomKeyEpoch: newEpoch,
        ),
      ),
      sig: Uint8List(0),
    );
    final memResult = _contentKey.signAndEncryptForRoom(
      memUnsigned,
      roomKey: newKey,
      roomEpoch: newEpoch,
      roomMsgSeq: 0,
    );
    await _storage.saveOwnEventWithEncrypted(
      memResult.signed,
      memResult.encrypted.toBytes(),
    );

    await _storage.saveRoom(
      room.copyWith(
        roomKey: newKey,
        roomKeyEpoch: newEpoch,
        roomKeyValidFrom: now,
        roomMsgSeqCounter: 1,
        membershipEpoch: newMembershipEpoch,
        lastActivityAt: now,
      ),
    );

    // 4. Re-seal the new key to every remaining member (excluding self) and
    //    fan the new roster out.
    final recipients = roster
        .where((p) => p != identity.pubkey)
        .toList(growable: false);
    await sealRoomKeyToMembers(
      crypto: _crypto,
      storage: _storage,
      roomId: roomId,
      senderPubkey: identity.pubkey,
      senderSecretKey: secretKey,
      roomKey: newKey,
      epoch: newEpoch,
      validFrom: now,
      recipientPubkeys: recipients,
    );
    for (final p in recipients) {
      await fanOutRoomEvent(_storage, p, roomId, memResult.encrypted.toBytes());
    }
  }
}
