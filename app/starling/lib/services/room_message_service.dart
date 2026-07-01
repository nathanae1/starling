import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import '../sync/room_delivery.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/crockford_base32.dart';
import 'crypto/publish_lock.dart';
import 'storage_service.dart';
import 'types.dart';

/// Authors durable chatroom text messages (Plan 17). Mirrors
/// [DefaultCommentService]: sign+encrypt under the room key, persist locally
/// (re-servable), then fan the wire bytes out to every other member via the
/// outbound queue. Held under the same [PublishLock] as room lifecycle so the
/// per-room `roomMsgSeqCounter` is allocated without races.
abstract class RoomMessageService {
  /// Author a text message in [roomId]. Returns the new message event id.
  Future<String> send({required String roomId, required String text});
}

class DefaultRoomMessageService implements RoomMessageService {
  DefaultRoomMessageService({
    required ContentKeyService contentKey,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    required PublishLock publishLock,
  }) : _contentKey = contentKey,
       _storage = storage,
       _clock = clock,
       _identityLookup = identityLookup,
       _publishLock = publishLock;

  final ContentKeyService _contentKey;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final PublishLock _publishLock;

  @override
  Future<String> send({required String roomId, required String text}) =>
      _publishLock.synchronized(() async {
        final identity = await _identityLookup();
        if (identity == null) {
          throw StateError('room send called before identity is loaded');
        }
        final room = await _storage.getRoom(roomId);
        if (room == null) throw StateError('room send: unknown room $roomId');
        if (!room.isMember) {
          throw StateError('room send: not a member of $roomId');
        }
        final now = _clock.nowUnixSeconds();
        final seq = room.roomMsgSeqCounter;

        final unsigned = Event(
          version: kStarlingProtocolVersion,
          id: '',
          pubkey: identity.pubkey,
          createdAt: now,
          kind: EventKind.roomMessage,
          ref: roomId,
          content: Uint8List.fromList(utf8.encode(text)),
          // Forward-compat: bind the roomId into the id-hashed extensions.
          extensions: {'room': crockfordBase32Decode(roomId)},
          sig: Uint8List(0),
        );
        final result = _contentKey.signAndEncryptForRoom(
          unsigned,
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

        // Fan out to every OTHER active member via the outbound queue.
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
        return result.signed.id;
      });
}
