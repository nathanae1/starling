import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:starling/models/voice_room.dart';
import 'package:starling/services/voice/ice_config.dart';
import 'package:starling/services/voice/webrtc_voice_service.dart';
import 'package:starling/services/voice_service.dart';

/// CI-runnable unit tests for [WebRtcVoiceService]'s orchestration logic.
///
/// The real flutter_webrtc engine (SDP/ICE negotiation over the native stack)
/// is exercised by the device-gated `webrtc_loopback_test.dart`. Here we inject
/// fake `RTCPeerConnection`/`MediaStream` via the service's factory seams and
/// verify the pure-Dart wiring: per-peer connection bookkeeping, local-track
/// attach, ICE/state stream forwarding, the connection-state mapping table,
/// mute via `track.enabled`, teardown, and audio-level polling — none of which
/// need a real WebRTC engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRtcVoiceService', () {
    test(
      'startSession acquires the local stream once and is idempotent',
      () async {
        final h = _Harness();
        await h.service.startSession('room1');
        expect(h.getUserMediaCalls, 1);
        // Same room → no re-acquire.
        await h.service.startSession('room1');
        expect(h.getUserMediaCalls, 1);
        await h.service.endSession();
      },
    );

    test(
      'startSession applies the current mute state to acquired tracks',
      () async {
        final h = _Harness();
        // Mute before any stream exists — just records intent.
        await h.service.setMicMuted(true);
        await h.service.startSession('r');
        expect(h.stream.tracks.every((t) => !t.enabled), isTrue);
        await h.service.endSession();
      },
    );

    test(
      'createOffer creates one peer connection and attaches local tracks',
      () async {
        final h = _Harness();
        await h.service.startSession('r');
        final offer = await h.service.createOffer('peerB');

        expect(offer['type'], 'offer');
        expect(offer['sdp'], isNotNull);
        expect(h.created, hasLength(1));
        expect(
          h.created.single.addedTracks,
          hasLength(h.stream.getAudioTracks().length),
        );
        expect(h.created.single.setLocalCount, 1);

        // A second offer to the same peer reuses the existing connection.
        await h.service.createOffer('peerB');
        expect(h.created, hasLength(1));
        await h.service.endSession();
      },
    );

    test(
      'createAnswer applies the remote offer and returns an answer',
      () async {
        final h = _Harness();
        await h.service.startSession('r');
        final answer = await h.service.createAnswer('peerB', {
          'sdp': 'remote-offer',
          'type': 'offer',
        });

        expect(answer['type'], 'answer');
        final pc = h.created.single;
        expect(pc.setRemoteCount, 1);
        expect(pc.setLocalCount, 1);
        await h.service.endSession();
      },
    );

    test(
      'local ICE candidates are forwarded tagged with the peer pubkey',
      () async {
        final h = _Harness();
        await h.service.startSession('r');
        final events = <VoiceIceCandidate>[];
        final sub = h.service.localIceCandidates.listen(events.add);

        await h.service.createOffer('peerB');
        h.created.single.onIceCandidate!(RTCIceCandidate('cand:1', 'audio', 0));
        await _flush();

        expect(events, hasLength(1));
        expect(events.single.peerPubkey, 'peerB');
        expect(events.single.candidate['candidate'], 'cand:1');
        expect(events.single.candidate['sdpMid'], 'audio');
        expect(events.single.candidate['sdpMLineIndex'], 0);

        await sub.cancel();
        await h.service.endSession();
      },
    );

    test('connection-state transitions map to participant states', () async {
      final table = {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            ParticipantConnectionState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateNew:
            ParticipantConnectionState.connecting,
        RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            ParticipantConnectionState.connecting,
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            ParticipantConnectionState.reconnecting,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            ParticipantConnectionState.disconnected,
        RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            ParticipantConnectionState.disconnected,
      };

      for (final entry in table.entries) {
        final h = _Harness();
        await h.service.startSession('r');
        final events = <VoicePeerState>[];
        final sub = h.service.peerStates.listen(events.add);

        await h.service.createOffer('peerB');
        h.created.single.onConnectionState!(entry.key);
        await _flush();

        expect(events, hasLength(1), reason: '${entry.key}');
        expect(events.single.peerPubkey, 'peerB');
        expect(events.single.state, entry.value, reason: '${entry.key}');

        await sub.cancel();
        await h.service.endSession();
      }
    });

    test('setMicMuted toggles every audio track and the getter', () async {
      final h = _Harness();
      await h.service.startSession('r');
      expect(h.service.micMuted, isFalse);

      await h.service.setMicMuted(true);
      expect(h.service.micMuted, isTrue);
      expect(h.stream.getAudioTracks().every((t) => !t.enabled), isTrue);

      await h.service.setMicMuted(false);
      expect(h.service.micMuted, isFalse);
      expect(h.stream.getAudioTracks().every((t) => t.enabled), isTrue);
      await h.service.endSession();
    });

    test('remote answer and ICE are ignored for unknown peers', () async {
      final h = _Harness();
      await h.service.startSession('r');
      // Must not throw and must not create a connection.
      await h.service.setRemoteAnswer('ghost', {'sdp': 's', 'type': 'answer'});
      await h.service.addRemoteIceCandidate('ghost', {
        'candidate': 'c',
        'sdpMid': 'a',
        'sdpMLineIndex': 0,
      });
      expect(h.created, isEmpty);
      await h.service.endSession();
    });

    test('remote answer and ICE reach the matching peer connection', () async {
      final h = _Harness();
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      final pc = h.created.single;

      await h.service.setRemoteAnswer('peerB', {
        'sdp': 'ans',
        'type': 'answer',
      });
      expect(pc.setRemoteCount, 1);

      await h.service.addRemoteIceCandidate('peerB', {
        'candidate': 'c',
        'sdpMid': 'a',
        'sdpMLineIndex': 1,
      });
      expect(pc.addedCandidates.single.candidate, 'c');
      expect(pc.addedCandidates.single.sdpMLineIndex, 1);
      await h.service.endSession();
    });

    test('removePeer closes and drops the connection', () async {
      final h = _Harness();
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      final first = h.created.single;

      await h.service.removePeer('peerB');
      expect(first.closed, isTrue);

      // A fresh offer creates a new connection.
      await h.service.createOffer('peerB');
      expect(h.created, hasLength(2));
      await h.service.endSession();
    });

    test(
      'endSession closes every peer, releases the stream, resets mute',
      () async {
        final h = _Harness();
        await h.service.startSession('r');
        await h.service.createOffer('a');
        await h.service.createOffer('b');
        await h.service.setMicMuted(true);

        await h.service.endSession();

        expect(h.created.every((pc) => pc.closed), isTrue);
        expect(h.stream.disposed, isTrue);
        expect(h.stream.tracks.every((t) => t.stopped), isTrue);
        expect(h.service.micMuted, isFalse);

        // A new session re-acquires the mic.
        await h.service.startSession('r2');
        expect(h.getUserMediaCalls, 2);
        await h.service.endSession();
      },
    );

    test('audio-level poll surfaces the loudest stat per peer', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      h.created.single.statsReports = [
        StatsReport('1', 'inbound-rtp', 0, {'audioLevel': 0.4}),
        StatsReport('2', 'inbound-rtp', 0, {'audioLevel': 0.7}),
      ];

      final levels = await h.service.audioLevels.first.timeout(
        const Duration(seconds: 2),
      );
      expect(levels['peerB'], 0.7);
      await h.service.endSession();
    });

    test('audio levels stay silent with no peers', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      var emitted = false;
      final sub = h.service.audioLevels.listen((_) => emitted = true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(emitted, isFalse);
      await sub.cancel();
      await h.service.endSession();
    });

    test('connection quality reports good for a clean link', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      h.created.single.statsReports = [
        StatsReport('ir', 'inbound-rtp', 0, {
          'packetsLost': 0,
          'packetsReceived': 100,
          'jitter': 0.001,
        }),
        StatsReport('cp', 'candidate-pair', 0, {
          'nominated': true,
          'currentRoundTripTime': 0.05,
        }),
      ];
      final q = await h.service.connectionQuality.first.timeout(
        const Duration(seconds: 2),
      );
      expect(q['peerB'], ConnectionQuality.good);
      await h.service.endSession();
    });

    test('connection quality reports poor under heavy packet loss', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      // Subscribe BEFORE seeding stats so the first emission is the cumulative
      // classification, before per-interval deltas zero the loss out. The 2s
      // timeout keeps it deterministic even under a congested full-suite run.
      final firstQuality = h.service.connectionQuality.first;
      h.created.single.statsReports = [
        StatsReport('ir', 'inbound-rtp', 0, {
          'packetsLost': 20,
          'packetsReceived': 80,
        }),
      ];
      final q = await firstQuality.timeout(const Duration(seconds: 2));
      expect(q['peerB'], ConnectionQuality.poor);
      await h.service.endSession();
    });

    test('connection quality reports fair for moderate loss', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      final firstQuality = h.service.connectionQuality.first;
      h.created.single.statsReports = [
        StatsReport('ir', 'inbound-rtp', 0, {
          'packetsLost': 5,
          'packetsReceived': 95,
        }),
      ];
      final q = await firstQuality.timeout(const Duration(seconds: 2));
      expect(q['peerB'], ConnectionQuality.fair);
      await h.service.endSession();
    });

    test('a peer with no RTP sample is absent from quality', () async {
      final h = _Harness(interval: const Duration(milliseconds: 10));
      await h.service.startSession('r');
      await h.service.createOffer('peerB');
      // Only an audio level, no inbound-rtp packet counters → no quality.
      h.created.single.statsReports = [
        StatsReport('1', 'inbound-rtp', 0, {'audioLevel': 0.5}),
      ];
      var emitted = false;
      final sub = h.service.connectionQuality.listen((_) => emitted = true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await sub.cancel();
      expect(emitted, isFalse);
      await h.service.endSession();
    });
  });
}

/// Lets queued microtasks (a synchronous `StreamController.add` → listener)
/// drain before assertions.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Builds a [WebRtcVoiceService] with fake WebRTC factories and exposes the
/// fakes for assertions. The same [_FakeMediaStream] is returned for every
/// `getUserMedia` call (counted via [getUserMediaCalls]); each
/// `peerConnectionFactory` call yields a fresh [_FakePeerConnection] recorded
/// in [created] (creation order == offer/answer call order in each test).
class _Harness {
  _Harness({Duration interval = const Duration(milliseconds: 600)}) {
    service = WebRtcVoiceService(
      iceConfigLookup: () async => const IceConfig(),
      audioLevelInterval: interval,
      peerConnectionFactory: (_) async {
        final pc = _FakePeerConnection();
        created.add(pc);
        return pc;
      },
      getUserMedia: (_) async {
        getUserMediaCalls++;
        return stream;
      },
    );
  }

  final List<_FakePeerConnection> created = [];
  final _FakeMediaStream stream = _FakeMediaStream();
  int getUserMediaCalls = 0;
  late final WebRtcVoiceService service;
}

class _FakeMediaStreamTrack implements MediaStreamTrack {
  bool _enabled = true;
  bool stopped = false;

  @override
  bool get enabled => _enabled;
  @override
  set enabled(bool b) => _enabled = b;
  @override
  Future<void> stop() async => stopped = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMediaStream implements MediaStream {
  _FakeMediaStream([int audioTracks = 1])
    : tracks = List.generate(audioTracks, (_) => _FakeMediaStreamTrack());

  final List<_FakeMediaStreamTrack> tracks;
  bool disposed = false;

  @override
  List<MediaStreamTrack> getTracks() => List.of(tracks);
  @override
  List<MediaStreamTrack> getAudioTracks() => List.of(tracks);
  @override
  Future<void> dispose() async => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRtpSender implements RTCRtpSender {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePeerConnection implements RTCPeerConnection {
  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;
  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  final List<MediaStreamTrack> addedTracks = [];
  final List<RTCIceCandidate> addedCandidates = [];
  List<StatsReport> statsReports = [];
  int setLocalCount = 0;
  int setRemoteCount = 0;
  bool closed = false;

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('offer-sdp', 'offer');

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('answer-sdp', 'answer');

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    setLocalCount++;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    setRemoteCount++;
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async =>
      statsReports;

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    addedTracks.add(track);
    return _FakeRtpSender();
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
