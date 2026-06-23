import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/voice_room.dart';
import '../voice_service.dart';
import 'ice_config.dart';

/// flutter_webrtc-backed [VoiceService] (Plan 16 §Phase B).
///
/// One [RTCPeerConnection] per remote participant (full mesh). The local mic
/// is a single [MediaStream] whose tracks are added to every peer connection.
/// `iceServers` is resolved from [IceConfig] at session start — empty by
/// default (host candidates only); audio is E2E via DTLS-SRTP.
class WebRtcVoiceService implements VoiceService {
  WebRtcVoiceService({
    required Future<IceConfig> Function() iceConfigLookup,
    Duration audioLevelInterval = const Duration(milliseconds: 600),
    // Injection seams for tests. Default to the real flutter_webrtc entry
    // points so production wiring is unchanged.
    Future<RTCPeerConnection> Function(Map<String, dynamic> configuration)
        peerConnectionFactory = createPeerConnection,
    Future<MediaStream> Function(Map<String, dynamic> constraints)? getUserMedia,
  })  : _iceConfigLookup = iceConfigLookup,
        _audioLevelInterval = audioLevelInterval,
        _peerConnectionFactory = peerConnectionFactory,
        _getUserMedia = getUserMedia ?? _defaultGetUserMedia;

  final Future<IceConfig> Function() _iceConfigLookup;
  final Duration _audioLevelInterval;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>)
      _peerConnectionFactory;
  final Future<MediaStream> Function(Map<String, dynamic>) _getUserMedia;

  static Future<MediaStream> _defaultGetUserMedia(
          Map<String, dynamic> constraints) =>
      navigator.mediaDevices.getUserMedia(constraints);

  final _localIce = StreamController<VoiceIceCandidate>.broadcast();
  final _peerStateCtrl = StreamController<VoicePeerState>.broadcast();
  final _audioLevelCtrl = StreamController<Map<String, double>>.broadcast();

  final Map<String, RTCPeerConnection> _peers = {};
  MediaStream? _localStream;
  Map<String, dynamic>? _rtcConfig;
  Timer? _levelTimer;
  bool _micMuted = false;
  bool _speakerMode = false;
  bool _inited = false;
  String? _roomId;

  @override
  Stream<VoiceIceCandidate> get localIceCandidates => _localIce.stream;
  @override
  Stream<VoicePeerState> get peerStates => _peerStateCtrl.stream;
  @override
  Stream<Map<String, double>> get audioLevels => _audioLevelCtrl.stream;
  @override
  bool get micMuted => _micMuted;
  @override
  bool get speakerMode => _speakerMode;

  @override
  Future<void> init() async {
    _inited = true;
  }

  @override
  Future<void> startSession(String roomId) async {
    if (!_inited) await init();
    if (_localStream != null && _roomId == roomId) return;
    _roomId = roomId;
    // iOS: route the AVAudioSession for two-way voice before capturing.
    try {
      await NativeAudioManagement.ensureAudioSession();
    } catch (_) {}
    final iceConfig = await _iceConfigLookup();
    _rtcConfig = iceConfig.toRtcConfiguration();
    _localStream ??= await _getUserMedia({
      'audio': true,
      'video': false,
    });
    _applyMuteToLocalTracks();
    _levelTimer ??= Timer.periodic(_audioLevelInterval, (_) => _pollLevels());
  }

  @override
  Future<Map<String, dynamic>> createOffer(String peerPubkey) async {
    final pc = await _peer(peerPubkey);
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  @override
  Future<Map<String, dynamic>> createAnswer(
    String peerPubkey,
    Map<String, dynamic> remoteOffer,
  ) async {
    final pc = await _peer(peerPubkey);
    await pc.setRemoteDescription(_sdp(remoteOffer));
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    return {'sdp': answer.sdp, 'type': answer.type};
  }

  @override
  Future<void> setRemoteAnswer(
    String peerPubkey,
    Map<String, dynamic> answer,
  ) async {
    final pc = _peers[peerPubkey];
    if (pc == null) return;
    await pc.setRemoteDescription(_sdp(answer));
  }

  @override
  Future<void> addRemoteIceCandidate(
    String peerPubkey,
    Map<String, dynamic> candidate,
  ) async {
    final pc = _peers[peerPubkey];
    if (pc == null) return;
    await pc.addCandidate(RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      (candidate['sdpMLineIndex'] as num?)?.toInt(),
    ));
  }

  @override
  Future<void> setMicMuted(bool muted) async {
    _micMuted = muted;
    _applyMuteToLocalTracks();
  }

  @override
  Future<void> setSpeakerMode(bool speaker) async {
    _speakerMode = speaker;
    try {
      await NativeAudioManagement.setSpeakerphoneOn(speaker);
    } catch (e) {
      developer.log('voice: setSpeakerphoneOn failed: $e', name: 'voice');
    }
  }

  @override
  Future<void> removePeer(String peerPubkey) async {
    final pc = _peers.remove(peerPubkey);
    if (pc == null) return;
    try {
      await pc.close();
    } catch (_) {}
  }

  @override
  Future<void> endSession() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    _roomId = null;
    _micMuted = false;
  }

  // --- internals ---

  Future<RTCPeerConnection> _peer(String peerPubkey) async {
    final existing = _peers[peerPubkey];
    if (existing != null) return existing;

    final pc = await _peerConnectionFactory(
      _rtcConfig ?? const {'iceServers': <Map<String, dynamic>>[]},
    );
    _peers[peerPubkey] = pc;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (_localIce.isClosed) return;
      _localIce.add(VoiceIceCandidate(
        peerPubkey: peerPubkey,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ));
    };
    pc.onConnectionState = (state) {
      if (_peerStateCtrl.isClosed) return;
      _peerStateCtrl
          .add(VoicePeerState(peerPubkey: peerPubkey, state: _mapState(state)));
    };
    return pc;
  }

  void _applyMuteToLocalTracks() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_micMuted;
    }
  }

  RTCSessionDescription _sdp(Map<String, dynamic> m) =>
      RTCSessionDescription(m['sdp'] as String?, m['type'] as String?);

  ParticipantConnectionState _mapState(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return ParticipantConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return ParticipantConnectionState.connecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return ParticipantConnectionState.reconnecting;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return ParticipantConnectionState.disconnected;
    }
  }

  Future<void> _pollLevels() async {
    if (_peers.isEmpty || _audioLevelCtrl.isClosed) return;
    final levels = <String, double>{};
    for (final entry in _peers.entries) {
      try {
        final reports = await entry.value.getStats();
        var best = 0.0;
        for (final r in reports) {
          final v = r.values['audioLevel'];
          if (v is num && v.toDouble() > best) best = v.toDouble();
        }
        if (best > 0) levels[entry.key] = best;
      } catch (_) {}
    }
    if (levels.isNotEmpty && !_audioLevelCtrl.isClosed) {
      _audioLevelCtrl.add(levels);
    }
  }
}
