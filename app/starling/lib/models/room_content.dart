import 'dart:typed_data';

import 'package:cbor/simple.dart';

/// CBOR codecs for Plan 17 chatroom event contents (kinds 100/101/103).
///
/// A `roomMessage` (kind 102) content is raw UTF-8 text and has no codec
/// here — it mirrors a comment body and is encoded with `utf8.encode` at the
/// author site. These codecs are the single source of truth for the CBOR
/// key names so writers ([RoomService]) and readers can't drift.

/// Decoded content of a `roomCreate` (kind 100) genesis event. The event's
/// id IS the roomId (content-addressed, identical for every member); this
/// content names the room and pins the creator.
class RoomCreateContent {
  const RoomCreateContent({
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
  });

  final String name;
  final String creatorPubkey;
  final int createdAt;
}

Uint8List encodeRoomCreateContent(RoomCreateContent content) =>
    Uint8List.fromList(
      cbor.encode({
        'name': content.name,
        'creator_pubkey': content.creatorPubkey,
        'created_at': content.createdAt,
      }),
    );

RoomCreateContent decodeRoomCreateContent(Uint8List bytes) {
  final map = cbor.decode(bytes) as Map<dynamic, dynamic>;
  return RoomCreateContent(
    name: map['name'] as String,
    creatorPubkey: map['creator_pubkey'] as String,
    createdAt: map['created_at'] as int,
  );
}

/// Decoded content of a `roomMembership` (kind 101) signed roster. Applied
/// only if `event.pubkey == creatorPubkey` and `membershipEpoch` is newer.
class RoomMembershipContent {
  const RoomMembershipContent({
    required this.members,
    required this.membershipEpoch,
    required this.roomKeyEpoch,
  });

  final List<String> members;
  final int membershipEpoch;
  final int roomKeyEpoch;
}

Uint8List encodeRoomMembershipContent(RoomMembershipContent content) =>
    Uint8List.fromList(
      cbor.encode({
        'members': content.members,
        'membership_epoch': content.membershipEpoch,
        'room_key_epoch': content.roomKeyEpoch,
      }),
    );

RoomMembershipContent decodeRoomMembershipContent(Uint8List bytes) {
  final map = cbor.decode(bytes) as Map<dynamic, dynamic>;
  return RoomMembershipContent(
    members: (map['members'] as List<dynamic>)
        .map((e) => e as String)
        .toList(growable: false),
    membershipEpoch: map['membership_epoch'] as int,
    roomKeyEpoch: map['room_key_epoch'] as int,
  );
}

/// Decoded content of a `roomCallStarted` (kind 103) durable record — the
/// no-server, no-push "Alice started a call" notice offline members see on
/// next sync. `callId` is a distinct domain from the chatroom `roomId`.
class RoomCallStartedContent {
  const RoomCallStartedContent({
    required this.callId,
    required this.starterPubkey,
  });

  final String callId;
  final String starterPubkey;
}

Uint8List encodeRoomCallStartedContent(RoomCallStartedContent content) =>
    Uint8List.fromList(
      cbor.encode({
        'call_id': content.callId,
        'starter_pubkey': content.starterPubkey,
      }),
    );

RoomCallStartedContent decodeRoomCallStartedContent(Uint8List bytes) {
  final map = cbor.decode(bytes) as Map<dynamic, dynamic>;
  return RoomCallStartedContent(
    callId: map['call_id'] as String,
    starterPubkey: map['starter_pubkey'] as String,
  );
}
