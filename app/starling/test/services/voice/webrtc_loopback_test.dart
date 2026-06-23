@Tags(['webrtc'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/voice_room.dart';
import 'package:starling/services/voice/ice_config.dart';
import 'package:starling/services/voice/webrtc_voice_service.dart';
import 'package:starling/services/voice_service.dart';

/// Plan 16 §Phase B — real-engine loopback integration test.
///
/// Spins up two real [WebRtcVoiceService] instances in the same process and
/// connects them to each other over loopback host candidates (empty
/// [IceConfig], no STUN/TURN), relaying SDP + ICE between them by hand the way
/// `RoomManager` would over the signaling plane. Validates the genuine
/// flutter_webrtc offer/answer/ICE path and DTLS-SRTP setup that the unit
/// tests stub out.
///
/// Requires a device/emulator with the native WebRTC engine — a host
/// `flutter test` cannot create a peer connection, so the group is skipped
/// off-device. Run with:
///   flutter test --tags webrtc test/services/voice/webrtc_loopback_test.dart
void main() {
  final onDevice = Platform.isAndroid || Platform.isIOS;

  group(
    'WebRtcVoiceService loopback',
    skip: onDevice ? null : 'requires an Android/iOS device or emulator',
    () {
      late WebRtcVoiceService alice;
      late WebRtcVoiceService bob;
      final subs = <StreamSubscription<dynamic>>[];

      setUp(() {
        alice = WebRtcVoiceService(iceConfigLookup: () async => const IceConfig());
        bob = WebRtcVoiceService(iceConfigLookup: () async => const IceConfig());
      });

      tearDown(() async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
        await alice.endSession();
        await bob.endSession();
      });

      test('two peers negotiate to connected over host candidates', () async {
        const aliceId = 'alice';
        const bobId = 'bob';

        await alice.startSession('room');
        await bob.startSession('room');

        // Relay each side's local ICE to the other (rewriting the peer tag to
        // the sender's identity, exactly as the signaling plane would).
        subs.add(alice.localIceCandidates.listen((c) {
          bob.addRemoteIceCandidate(aliceId, c.candidate);
        }));
        subs.add(bob.localIceCandidates.listen((c) {
          alice.addRemoteIceCandidate(bobId, c.candidate);
        }));

        final aliceConnected = _firstConnected(alice, bobId, subs);
        final bobConnected = _firstConnected(bob, aliceId, subs);

        // Offer/answer exchange.
        final offer = await alice.createOffer(bobId);
        final answer = await bob.createAnswer(aliceId, offer);
        await alice.setRemoteAnswer(bobId, answer);

        await Future.wait([aliceConnected, bobConnected])
            .timeout(const Duration(seconds: 20));
      });
    },
  );
}

/// Completes when [svc] reports [peer] as connected.
Future<void> _firstConnected(
  VoiceService svc,
  String peer,
  List<StreamSubscription<dynamic>> subs,
) {
  final done = Completer<void>();
  subs.add(svc.peerStates.listen((s) {
    if (s.peerPubkey == peer &&
        s.state == ParticipantConnectionState.connected &&
        !done.isCompleted) {
      done.complete();
    }
  }));
  return done.future;
}
