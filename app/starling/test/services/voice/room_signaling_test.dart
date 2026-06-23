import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/signaling_message.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/mocks/mock_signaling_service.dart';
import 'package:starling/services/signaling/signaling_dispatcher.dart';
import 'package:starling/services/voice/room_signaling.dart';

/// A peer's signaling stack: mock transport + dispatcher + RoomSignaling.
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
    dispatcher.start();
    roomSignaling.start();
  }

  final String pubkey;
  final MockCryptoService crypto;
  final _secret = Uint8List(64);
  late final MockSignalingService signaling;
  late final SignalingDispatcher dispatcher;
  late final RoomSignaling roomSignaling;
}

String _pk(int fill) =>
    crockfordBase32Encode(Uint8List.fromList(List.filled(32, fill)));

Future<void> _pump() => Future.delayed(const Duration(milliseconds: 20));

void main() {
  final crypto = MockCryptoService();
  final pkA = _pk(1);
  final pkB = _pk(2);
  final pkC = _pk(3);

  late _Peer a;
  late _Peer b;

  setUp(() {
    a = _Peer(pkA, crypto);
    b = _Peer(pkB, crypto);
    a.signaling.link(b.signaling);
  });

  test('sendTo delivers a voice message to the recipient inbound stream',
      () async {
    final received = <VoiceSignal>[];
    b.roomSignaling.inbound.listen(received.add);

    await a.roomSignaling.sendTo(pkB,
        type: SignalingMessageType.roomInvite,
        roomId: 'room1',
        payload: {'name': 'Hi'});
    await _pump();

    expect(received, hasLength(1));
    expect(received.first.message.type, SignalingMessageType.roomInvite);
    expect(received.first.message.roomId, 'room1');
    expect(received.first.message.senderPubkey, pkA);
    expect(received.first.message.payload['name'], 'Hi');
  });

  test('fanOut delivers a copy to every recipient', () async {
    final c = _Peer(pkC, crypto);
    a.signaling.link(c.signaling);

    final gotB = <VoiceSignal>[];
    final gotC = <VoiceSignal>[];
    b.roomSignaling.inbound.listen(gotB.add);
    c.roomSignaling.inbound.listen(gotC.add);

    await a.roomSignaling.fanOut(
      [pkB, pkC],
      type: SignalingMessageType.roomInvite,
      roomId: 'r',
      payload: {'x': 1},
    );
    await _pump();

    expect(gotB, hasLength(1));
    expect(gotC, hasLength(1));
    expect(gotB.first.message.roomId, 'r');
    expect(gotC.first.message.roomId, 'r');
  });

  test('duplicate inbound bytes are deduped', () async {
    final gotB = <VoiceSignal>[];
    b.roomSignaling.inbound.listen(gotB.add);

    await a.roomSignaling.sendTo(pkB,
        type: SignalingMessageType.offer, roomId: 'r', payload: {'sdp': 's'});
    await _pump();
    expect(gotB, hasLength(1));

    // Re-deliver the identical sealed envelope on B's inbound channel.
    final aToB = a.signaling.activeChannels[pkB]! as MockSignalingChannel;
    final bInbound = b.signaling.activeChannels[pkA]! as MockSignalingChannel;
    bInbound.simulateReceive(aToB.sentMessages.last);
    await _pump();

    expect(gotB, hasLength(1), reason: 'duplicate must be deduped');
  });

  test('libp2pConnect is never surfaced as a voice signal', () async {
    final gotB = <VoiceSignal>[];
    b.roomSignaling.inbound.listen(gotB.add);

    await a.roomSignaling.sendTo(pkB,
        type: SignalingMessageType.libp2pConnect,
        roomId: '',
        payload: {'peer_id': 'x'});
    await _pump();

    expect(gotB, isEmpty);
  });
}
