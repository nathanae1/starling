import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/voice_room.dart';

VoiceParticipant _p(String pk, ParticipantConnectionState state) =>
    VoiceParticipant(pubkey: pk, connectionState: state);

VoiceRoomState _state(List<VoiceParticipant> participants) => VoiceRoomState(
  room: VoiceRoom(
    id: 'r',
    name: 'Room',
    creatorPubkey: 'me',
    createdAt: 0,
    participants: participants,
  ),
);

void main() {
  group('VoiceRoomState.anyReconnecting', () {
    test('false when everyone is connected', () {
      expect(
        _state([
          _p('me', ParticipantConnectionState.connected),
          _p('a', ParticipantConnectionState.connected),
        ]).anyReconnecting,
        isFalse,
      );
    });

    test('true when a remote peer is reconnecting', () {
      expect(
        _state([
          _p('me', ParticipantConnectionState.connected),
          _p('a', ParticipantConnectionState.reconnecting),
        ]).anyReconnecting,
        isTrue,
      );
    });

    test('only reconnecting counts — connecting/disconnected do not', () {
      // `disconnected` is terminal ("unreachable"), `connecting` is the initial
      // join; the call-wide banner is specifically for the transient recovery.
      expect(
        _state([
          _p('me', ParticipantConnectionState.connected),
          _p('a', ParticipantConnectionState.connecting),
          _p('b', ParticipantConnectionState.disconnected),
        ]).anyReconnecting,
        isFalse,
      );
    });
  });
}
