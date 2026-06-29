import 'package:cbor/simple.dart';
import 'dart:typed_data';

/// Types of signaling messages exchanged over the WebSocket channel.
enum SignalingMessageType {
  roomInvite('room_invite'),
  roomAccept('room_accept'),
  roomDecline('room_decline'),
  roomLeave('room_leave'),
  roomClose('room_close'),
  offer('offer'),
  answer('answer'),
  iceCandidate('ice_candidate'),
  muteStatus('mute_status'),
  // Plan 11a — DCUtR hole-punch coordination. payload shape:
  //   { peer_id: String,           // sender's libp2p PeerId (base58)
  //     observed_addrs: List<Uint8List>, // candidate multiaddrs (STUN +
  //                                     // local listen) the sender is
  //                                     // willing to be dialed at
  //     nonce: Uint8List,           // 8 random bytes, echoed in response
  //     punch_at_unix_ms: int }     // proposed simultaneous-open time
  // roomId for this type is always the empty string — the message is a
  // pairwise exchange, not bound to a voice room.
  libp2pConnect('libp2p-connect-v1');

  const SignalingMessageType(this.value);
  final String value;

  static SignalingMessageType fromValue(String value) {
    return SignalingMessageType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw ArgumentError('Unknown SignalingMessageType: $value'),
    );
  }
}

/// A real-time signaling message exchanged between peers over WebSocket.
///
/// Used for voice room setup, WebRTC negotiation (SDP offer/answer, ICE
/// candidates), and room lifecycle events. These messages are ephemeral
/// and never stored in the feed.
class SignalingMessage {
  const SignalingMessage({
    required this.type,
    required this.roomId,
    required this.senderPubkey,
    required this.payload,
    required this.timestamp,
  });

  final SignalingMessageType type;
  final String roomId;
  final String senderPubkey;
  final Map<String, dynamic> payload;
  final int timestamp;

  Map<String, dynamic> toMap() => {
    'type': type.value,
    'room_id': roomId,
    'sender_pubkey': senderPubkey,
    'payload': payload,
    'timestamp': timestamp,
  };

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static SignalingMessage fromMap(Map<dynamic, dynamic> map) =>
      SignalingMessage(
        type: SignalingMessageType.fromValue(map['type'] as String),
        roomId: map['room_id'] as String,
        senderPubkey: map['sender_pubkey'] as String,
        payload: _castPayload(map['payload']),
        timestamp: map['timestamp'] as int,
      );

  static SignalingMessage fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalingMessage &&
          type == other.type &&
          roomId == other.roomId &&
          senderPubkey == other.senderPubkey &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(type, roomId, senderPubkey, timestamp);

  @override
  String toString() =>
      'SignalingMessage(type: ${type.value}, room: $roomId, '
      'sender: $senderPubkey)';
}

Map<String, dynamic> _castPayload(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return {};
}
