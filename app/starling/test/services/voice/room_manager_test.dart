import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/signaling_message.dart';
import 'package:starling/models/voice_room.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/mocks/mock_signaling_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/mocks/mock_voice_service.dart';
import 'package:starling/services/signaling/signaling_dispatcher.dart';
import 'package:starling/services/voice/room_manager.dart';
import 'package:starling/services/voice/room_signaling.dart';
import 'package:starling/services/types.dart';

class _Peer {
  _Peer(this.pubkey, this.crypto) {
    signaling = MockSignalingService(localPubkey: pubkey);
    dispatcher = SignalingDispatcher(
      signaling: signaling,
      crypto: crypto,
      localPubkeyLookup: () async => pubkey,
      localSecretKeyLookup: () async => _secret,
    );
    roomSignaling = RoomSignaling(
      signaling: signaling,
      dispatcher: dispatcher,
      crypto: crypto,
      clock: const SystemClock(),
      localPubkeyLookup: () async => pubkey,
      localSecretKeyLookup: () async => _secret,
    );
    manager = RoomManager(
      roomSignaling: roomSignaling,
      voice: voice,
      storage: storage,
      crypto: crypto,
      clock: const SystemClock(),
      localPubkeyLookup: () async => pubkey,
    );
    dispatcher.start();
    manager.start();
  }

  final String pubkey;
  final MockCryptoService crypto;
  final _secret = Uint8List(64);
  final storage = MockStorageService();
  final voice = MockVoiceService();
  late final MockSignalingService signaling;
  late final SignalingDispatcher dispatcher;
  late final RoomSignaling roomSignaling;
  late final RoomManager manager;

  /// Make [other] a mutual follow: we follow them (active) and they follow us
  /// (accepted inbound request).
  Future<void> makeMutual(String other) async {
    await storage.saveFollow(Follow(
      pubkey: other,
      connectionCard: '',
      feedKey: Uint8List(32),
    ));
    await storage.saveInboundRequest(FollowRequest(
      pubkey: other,
      payload: Uint8List(0),
      createdAt: 0,
      requestTimestamp: 0,
      status: 'accepted',
    ));
  }
}

String _pk(int fill) =>
    crockfordBase32Encode(Uint8List.fromList(List.filled(32, fill)));

Future<void> _pump() => Future.delayed(const Duration(milliseconds: 30));

void main() {
  final crypto = MockCryptoService();
  final pkA = _pk(1);
  final pkB = _pk(2);
  final pkX = _pk(9);

  late _Peer a;
  late _Peer b;

  setUp(() async {
    a = _Peer(pkA, crypto);
    b = _Peer(pkB, crypto);
    a.signaling.link(b.signaling);
    await a.makeMutual(pkB);
    await b.makeMutual(pkA);
  });

  test('create → invite → accept establishes exactly one offer/answer pair',
      () async {
    final bInvites = <VoiceRoom>[];
    b.manager.incomingInvites.listen(bInvites.add);

    final room = await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
    await _pump();

    expect(bInvites, hasLength(1));
    expect(bInvites.first.id, room.id);
    expect(bInvites.first.name, 'Chat');
    expect(bInvites.first.creatorPubkey, pkA);

    await b.manager.acceptInvite(room.id);
    await _pump();

    // Exactly one side is the offerer (lexicographic pubkey rule).
    final aOfferedB = a.voice.offeredPeers.contains(pkB);
    final bOfferedA = b.voice.offeredPeers.contains(pkA);
    expect(aOfferedB ^ bOfferedA, isTrue,
        reason: 'exactly one peer offers, the other answers');
    if (aOfferedB) {
      expect(b.voice.answeredPeers, contains(pkA));
    } else {
      expect(a.voice.answeredPeers, contains(pkB));
    }

    // Both rosters know each other.
    expect(a.manager.currentState!.room.participants.map((p) => p.pubkey),
        containsAll([pkA, pkB]));
    expect(b.manager.currentState!.room.participants.map((p) => p.pubkey),
        containsAll([pkA, pkB]));

    // Both sessions are live on the mock WebRTC engine.
    expect(a.voice.sessionRoomId, room.id);
    expect(b.voice.sessionRoomId, room.id);
  });

  test('createRoom rejects a non-mutual-follow invitee', () async {
    // pkX is not a follow of A.
    expect(
      () => a.manager.createRoom(name: 'x', inviteePubkeys: [pkX]),
      throwsStateError,
    );
  });

  test('createRoom enforces the 4-person cap (max 3 invitees)', () async {
    expect(
      () => a.manager.createRoom(
        name: 'x',
        inviteePubkeys: [_pk(2), _pk(3), _pk(4), _pk(5)],
      ),
      throwsArgumentError,
    );
  });

  test('decline does not start a session', () async {
    final room = await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
    await _pump();
    await b.manager.declineInvite(room.id);
    await _pump();
    expect(b.manager.inCall, isFalse);
    expect(b.voice.sessionRoomId, isNull);
  });

  test('creator closing the room ends the callee session', () async {
    final room = await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
    await _pump();
    await b.manager.acceptInvite(room.id);
    await _pump();
    expect(b.manager.inCall, isTrue);

    await a.manager.closeRoom();
    await _pump();

    expect(a.manager.inCall, isFalse);
    expect(b.manager.inCall, isFalse, reason: 'roomClose tears down the callee');
    expect(a.voice.sessionEnded, isTrue);
    expect(b.voice.sessionEnded, isTrue);
  });

  test('mute broadcasts mute status to the peer', () async {
    final room = await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
    await _pump();
    await b.manager.acceptInvite(room.id);
    await _pump();

    await a.manager.setMuted(true);
    await _pump();

    expect(a.voice.micMuted, isTrue);
    final bParticipantA = b.manager.currentState!.room.participants
        .firstWhere((p) => p.pubkey == pkA);
    expect(bParticipantA.isMuted, isTrue);
  });
}
