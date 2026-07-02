import 'dart:async';

import '../../models/voice_room.dart';
import '../voice_service.dart';

/// In-memory [VoiceService] for tests — no platform bindings. Produces fake
/// SDP/ICE payloads and records calls so room-management tests can assert the
/// orchestration without a real WebRTC stack.
class MockVoiceService implements VoiceService {
  final _localIce = StreamController<VoiceIceCandidate>.broadcast();
  final _peerStateCtrl = StreamController<VoicePeerState>.broadcast();
  final _audioLevelCtrl = StreamController<Map<String, double>>.broadcast();
  final _qualityCtrl =
      StreamController<Map<String, ConnectionQuality>>.broadcast();
  final _renegotiationCtrl = StreamController<String>.broadcast();

  bool _micMuted = false;
  bool _speakerMode = false;
  String? sessionRoomId;

  /// Peers we've created an offer for, in order.
  final List<String> offeredPeers = [];

  /// Peers we've answered, in order.
  final List<String> answeredPeers = [];

  /// Peers torn down via [removePeer].
  final List<String> removedPeers = [];

  /// Remote ICE candidates we've been handed, by peer.
  final Map<String, List<Map<String, dynamic>>> remoteCandidates = {};

  bool sessionEnded = false;

  @override
  Stream<VoiceIceCandidate> get localIceCandidates => _localIce.stream;
  @override
  Stream<VoicePeerState> get peerStates => _peerStateCtrl.stream;
  @override
  Stream<Map<String, double>> get audioLevels => _audioLevelCtrl.stream;
  @override
  Stream<Map<String, ConnectionQuality>> get connectionQuality =>
      _qualityCtrl.stream;
  @override
  Stream<String> get renegotiationNeeded => _renegotiationCtrl.stream;
  @override
  bool get micMuted => _micMuted;
  @override
  bool get speakerMode => _speakerMode;

  @override
  Future<void> init() async {}

  @override
  Future<void> startSession(String roomId) async {
    sessionRoomId = roomId;
    sessionEnded = false;
  }

  @override
  Future<Map<String, dynamic>> createOffer(String peerPubkey) async {
    offeredPeers.add(peerPubkey);
    return {'sdp': 'mock-offer:$peerPubkey', 'type': 'offer'};
  }

  @override
  Future<Map<String, dynamic>> createAnswer(
    String peerPubkey,
    Map<String, dynamic> remoteOffer,
  ) async {
    answeredPeers.add(peerPubkey);
    return {'sdp': 'mock-answer:$peerPubkey', 'type': 'answer'};
  }

  @override
  Future<void> setRemoteAnswer(
    String peerPubkey,
    Map<String, dynamic> answer,
  ) async {}

  @override
  Future<void> addRemoteIceCandidate(
    String peerPubkey,
    Map<String, dynamic> candidate,
  ) async {
    (remoteCandidates[peerPubkey] ??= []).add(candidate);
  }

  @override
  Future<void> setMicMuted(bool muted) async => _micMuted = muted;

  @override
  Future<void> setSpeakerMode(bool speaker) async => _speakerMode = speaker;

  @override
  Future<void> removePeer(String peerPubkey) async =>
      removedPeers.add(peerPubkey);

  @override
  Future<void> endSession() async {
    sessionEnded = true;
    sessionRoomId = null;
  }

  // --- test helpers ---

  void emitLocalIce(String peerPubkey, Map<String, dynamic> candidate) =>
      _localIce.add(
        VoiceIceCandidate(peerPubkey: peerPubkey, candidate: candidate),
      );

  void emitPeerState(String peerPubkey, ParticipantConnectionState state) =>
      _peerStateCtrl.add(VoicePeerState(peerPubkey: peerPubkey, state: state));

  void emitAudioLevels(Map<String, double> levels) =>
      _audioLevelCtrl.add(levels);

  void emitConnectionQuality(Map<String, ConnectionQuality> quality) =>
      _qualityCtrl.add(quality);

  void emitRenegotiationNeeded(String peerPubkey) =>
      _renegotiationCtrl.add(peerPubkey);
}
