import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../models/models.dart';
import '../../services/clock.dart';
import '../../services/content_key_service.dart';
import '../../services/crypto/crockford_base32.dart';
import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';
import '../../sync/room_delivery.dart';
import '../../sync/sealed_delivery.dart';

/// Plan 17 chatroom ingestion for pushed `room-key` / `room-event` items.
/// Called from `ingestPushedEnvelope`, with `room-key` processed before
/// `room-event` in the same envelope so a fresh key is available to decrypt.

/// Ingest a `room-key` item: unseal the DH-sealed room key (which doubles as
/// a possession proof), require the sealer to be a mutual follow, then store
/// the key — provisioning the room row on first contact, or archiving the
/// current key and adopting a newer epoch on rotation.
Future<void> ingestRoomKeyItem({
  required StorageService storage,
  required CryptoService crypto,
  required Clock clock,
  required Identity identity,
  required Uint8List ownSecretKey,
  required Uint8List payload,
}) async {
  final RoomKeyDelivery delivery;
  try {
    delivery = RoomKeyDelivery.fromBytes(payload);
  } catch (e) {
    developer.log('room-key: bad cbor: $e', name: 'room_ingest');
    return;
  }

  // Auth: only accept keys sealed by a current mutual follow.
  final follow = await storage.getFollow(delivery.sender);
  if (follow == null || follow.status != 'active') return;
  if (!await storage.isAcceptedFollower(delivery.sender)) return;

  // Unseal (reverse the DH). Failure ⇒ tampered / not sealed for us.
  final Uint8List roomKey;
  try {
    roomKey = unsealDeliveryPayload(
      crypto,
      senderEdPk: crockfordBase32Decode(delivery.sender),
      recipientEdPk: crockfordBase32Decode(identity.pubkey),
      recipientSecretKey: ownSecretKey,
      delivery: delivery.sealed,
    );
  } catch (e) {
    developer.log('room-key: unseal failed: $e', name: 'room_ingest');
    return;
  }

  final now = clock.nowUnixSeconds();
  final existing = await storage.getRoom(delivery.roomId);

  if (existing == null) {
    // First contact — provisional row; roomCreate fills name/creator later.
    await storage.saveRoom(
      Room(
        id: delivery.roomId,
        name: '',
        creatorPubkey: delivery.sender,
        createdAt: now,
        lastActivityAt: now,
        roomKey: roomKey,
        roomKeyEpoch: delivery.epoch,
        roomKeyValidFrom: delivery.validFrom,
        roomMsgSeqCounter: 0,
        membershipEpoch: 0,
        isMember: true,
        lastReadAt: 0,
      ),
    );
    await storage.saveRoomMember(
      RoomMember(
        roomId: delivery.roomId,
        pubkey: identity.pubkey,
        addedAt: now,
      ),
    );
    return;
  }

  if (delivery.epoch > existing.roomKeyEpoch) {
    // Rotation: archive the current key with its window, then adopt the new.
    await storage.appendRoomKeyHistory(
      delivery.roomId,
      roomKey: existing.roomKey,
      epoch: existing.roomKeyEpoch,
      validFrom: existing.roomKeyValidFrom == 0
          ? existing.createdAt
          : existing.roomKeyValidFrom,
      validUntil: delivery.validFrom,
    );
    await storage.saveRoom(
      existing.copyWith(
        roomKey: roomKey,
        roomKeyEpoch: delivery.epoch,
        roomKeyValidFrom: delivery.validFrom,
        roomMsgSeqCounter: 0,
        isMember: true,
      ),
    );
  } else if (delivery.epoch < existing.roomKeyEpoch) {
    // Out-of-order older key — archive it (if new) so its window stays
    // decryptable.
    final history = await storage.getRoomKeyHistory(delivery.roomId);
    if (!history.any((h) => h.epoch == delivery.epoch)) {
      await storage.appendRoomKeyHistory(
        delivery.roomId,
        roomKey: roomKey,
        epoch: delivery.epoch,
        validFrom: delivery.validFrom,
        validUntil: existing.roomKeyValidFrom,
      );
    }
  } else if (!existing.isMember) {
    // Same epoch, re-added after leaving — restore membership.
    await storage.saveRoom(existing.copyWith(isMember: true));
  }
}

/// Ingest a `room-event` item: select the room key (current + history windows
/// covering the message time), decrypt, verify the author is a current member
/// (or the creator), and apply the event by kind.
Future<void> ingestRoomEventItem({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Clock clock,
  required Identity identity,
  required Uint8List payload,
}) async {
  final RoomEventDelivery delivery;
  try {
    delivery = RoomEventDelivery.fromBytes(payload);
  } catch (e) {
    developer.log('room-event: bad cbor: $e', name: 'room_ingest');
    return;
  }
  final room = await storage.getRoom(delivery.roomId);
  if (room == null) return; // no room key yet — drop (key is processed first)

  final EncryptedEvent encrypted;
  try {
    encrypted = EncryptedEvent.fromBytes(delivery.event);
  } catch (e) {
    developer.log('room-event: bad event bytes: $e', name: 'room_ingest');
    return;
  }

  // Author must be the creator or a currently-active member.
  final members = await storage.getRoomMembers(delivery.roomId);
  final authorIsMember = members.any(
    (m) => m.pubkey == encrypted.pubkey && m.isActive,
  );
  if (!authorIsMember && encrypted.pubkey != room.creatorPubkey) return;

  // Candidate keys: current key + any retired key whose window covers the
  // message's createdAt (mirrors SyncEngine feed-key candidate selection).
  final candidates = <Uint8List>[room.roomKey];
  for (final h in await storage.getRoomKeyHistory(delivery.roomId)) {
    if (h.validFrom <= encrypted.createdAt &&
        encrypted.createdAt < h.validUntil) {
      candidates.add(h.roomKey);
    }
  }
  Event? decrypted;
  for (final key in candidates) {
    try {
      decrypted = contentKey.decryptEvent(encrypted, key);
      break;
    } catch (_) {
      // wrong candidate — try the next
    }
  }
  if (decrypted == null) {
    developer.log(
      'room-event: no candidate key decrypted for ${delivery.roomId}',
      name: 'room_ingest',
    );
    return;
  }
  await _applyRoomEvent(
    storage,
    clock,
    identity,
    room,
    decrypted.copyWith(msgSeq: encrypted.msgSeq),
    delivery.event,
  );
}

Future<void> _applyRoomEvent(
  StorageService storage,
  Clock clock,
  Identity identity,
  Room room,
  Event event,
  Uint8List wireBytes,
) async {
  switch (event.kind.value) {
    case 100: // roomCreate — fill in name/creator/createdAt on the row.
      if (event.id != room.id) return; // genesis id must equal roomId
      final content = decodeRoomCreateContent(event.content);
      await storage.saveIncomingEventWithEncrypted(event, wireBytes);
      await storage.saveRoom(
        Room(
          id: room.id,
          name: content.name,
          creatorPubkey: content.creatorPubkey,
          createdAt: content.createdAt,
          lastActivityAt: room.lastActivityAt,
          roomKey: room.roomKey,
          roomKeyEpoch: room.roomKeyEpoch,
          roomKeyValidFrom: room.roomKeyValidFrom,
          roomMsgSeqCounter: room.roomMsgSeqCounter,
          membershipEpoch: room.membershipEpoch,
          isMember: room.isMember,
          lastReadAt: room.lastReadAt,
        ),
      );
    case 101: // roomMembership — creator-only; newest epoch wins.
      if (event.pubkey != room.creatorPubkey) return;
      await storage.saveIncomingEventWithEncrypted(event, wireBytes);
      final content = decodeRoomMembershipContent(event.content);
      if (content.membershipEpoch <= room.membershipEpoch) return;
      await _applyRoster(storage, clock, identity, room, content);
    case 102: // roomMessage
    case 103: // roomCallStarted
      await storage.saveIncomingEventWithEncrypted(event, wireBytes);
      // Pin joined-room messages so retention's 30d event prune skips them.
      if (room.isMember) await storage.setEventSaved(event.id, true);
      if (event.createdAt > room.lastActivityAt) {
        await storage.updateRoomActivity(room.id, event.createdAt);
      }
  }
}

Future<void> _applyRoster(
  StorageService storage,
  Clock clock,
  Identity identity,
  Room room,
  RoomMembershipContent content,
) async {
  final now = clock.nowUnixSeconds();
  final newSet = content.members.toSet();
  final current = await storage.getRoomMembers(room.id);
  final currentByPk = {for (final m in current) m.pubkey: m};

  // Removals: active members dropped from the roster.
  for (final m in current) {
    if (m.isActive && !newSet.contains(m.pubkey)) {
      await storage.setRoomMemberRemoved(room.id, m.pubkey, now);
    }
  }
  // Additions / re-adds.
  for (final pk in content.members) {
    final existing = currentByPk[pk];
    if (existing == null) {
      await storage.saveRoomMember(
        RoomMember(roomId: room.id, pubkey: pk, addedAt: now),
      );
    } else if (!existing.isActive) {
      await storage.saveRoomMember(
        RoomMember(roomId: room.id, pubkey: pk, addedAt: existing.addedAt),
      );
    }
  }

  await storage.saveRoom(
    room.copyWith(
      membershipEpoch: content.membershipEpoch,
      isMember: newSet.contains(identity.pubkey),
    ),
  );
}
