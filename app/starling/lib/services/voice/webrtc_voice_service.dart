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
        peerConnectionFactory =
        createPeerConnection,
    Future<MediaStream> Function(Map<String, dynamic> constraints)?
    getUserMedia,
  }) : _iceConfigLookup = iceConfigLookup,
       _audioLevelInterval = audioLevelInterval,
       _peerConnectionFactory = peerConnectionFactory,
       _getUserMedia = getUserMedia ?? _defaultGetUserMedia;

  final Future<IceConfig> Function() _iceConfigLookup;
  final Duration _audioLevelInterval;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>)
  _peerConnectionFactory;
  final Future<MediaStream> Function(Map<String, dynamic>) _getUserMedia;

  static Future<MediaStream> _defaultGetUserMedia(
    Map<String, dynamic> constraints,
  ) => navigator.mediaDevices.getUserMedia(constraints);

  final _localIce = StreamController<VoiceIceCandidate>.broadcast();
  final _peerStateCtrl = StreamController<VoicePeerState>.broadcast();
  final _audioLevelCtrl = StreamController<Map<String, double>>.broadcast();
  final _qualityCtrl =
      StreamController<Map<String, ConnectionQuality>>.broadcast();
  final _renegotiationCtrl = StreamController<String>.broadcast();

  final Map<String, RTCPeerConnection> _peers = {};
  // Peers granted their one-shot ICE restart after a Failed state. Cleared
  // when the peer reconnects (or is torn down); a second Failed while still
  // in this set is terminal.
  final Set<String> _iceRestarted = {};
  // Per-peer previous cumulative RTP counters, for per-interval loss deltas.
  final Map<String, _QualitySample> _qualitySamples = {};
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
  Stream<Map<String, ConnectionQuality>> get connectionQuality =>
      _qualityCtrl.stream;
  @override
  Stream<String> get renegotiationNeeded => _renegotiationCtrl.stream;
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
    _localStream ??= await _getUserMedia({'audio': true, 'video': false});
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
    await pc.addCandidate(
      RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        (candidate['sdpMLineIndex'] as num?)?.toInt(),
      ),
    );
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
    _qualitySamples.remove(peerPubkey);
    _iceRestarted.remove(peerPubkey);
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
    _qualitySamples.clear();
    _iceRestarted.clear();
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
      _localIce.add(
        VoiceIceCandidate(
          peerPubkey: peerPubkey,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };
    pc.onConnectionState = (state) {
      if (_peerStateCtrl.isClosed) return;
      var mapped = _mapState(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !_iceRestarted.contains(peerPubkey)) {
        // One-shot ICE restart before declaring the peer gone — a mid-call
        // network blip (Wi-Fi → cellular, Tor circuit rebuild) commonly
        // lands here. restartIce() flags renegotiation; the room manager
        // re-runs the offer exchange via [renegotiationNeeded]. A second
        // Failed is terminal.
        _iceRestarted.add(peerPubkey);
        try {
          pc.restartIce();
          mapped = ParticipantConnectionState.reconnecting;
          if (!_renegotiationCtrl.isClosed) {
            _renegotiationCtrl.add(peerPubkey);
          }
        } catch (e) {
          developer.log('voice: restartIce failed: $e', name: 'voice');
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _iceRestarted.remove(peerPubkey);
      }
      _peerStateCtrl.add(VoicePeerState(peerPubkey: peerPubkey, state: mapped));
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

  // Connection-quality thresholds (tunable). `loss` is a per-interval fraction;
  // `rtt`/`jitter` are seconds (WebRTC stats units).
  static const _lossGood = 0.02;
  static const _lossPoor = 0.08;
  static const _rttGood = 0.20;
  static const _rttPoor = 0.40;
  static const _jitterGood = 0.03;

  Future<void> _pollLevels() async {
    if (_peers.isEmpty) return;
    final levels = <String, double>{};
    final quality = <String, ConnectionQuality>{};
    for (final entry in _peers.entries) {
      try {
        // One getStats() per peer feeds BOTH speaking detection and link
        // quality — deliberately no second poll loop.
        final reports = await entry.value.getStats();
        var best = 0.0;
        int? packetsLost;
        int? packetsReceived;
        double? jitter;
        double? rtt;
        for (final r in reports) {
          final v = r.values;

          if (r.type == 'inbound-rtp') {
            // Voice-only mesh → the sole inbound-rtp stream is the peer's
            // audio. The peer's level must come from HERE only: the same
            // stats dump carries the local `media-source` level, and taking
            // the max over all reports lit remote rings with your own voice.
            final level = v['audioLevel'];
            if (level is num && level.toDouble() > best) {
              best = level.toDouble();
            }
            final pl = v['packetsLost'];
            final pr = v['packetsReceived'];
            final j = v['jitter'];
            if (pl is num) packetsLost = pl.toInt();
            if (pr is num) packetsReceived = pr.toInt();
            if (j is num) jitter = j.toDouble();
          } else if (r.type == 'media-source') {
            // Local mic level — reported once under the reserved self key
            // ("my mic works" feedback), never against a peer.
            final level = v['audioLevel'];
            if (level is num) {
              final self = level.toDouble();
              if (self > (levels[kSelfAudioLevelKey] ?? 0)) {
                levels[kSelfAudioLevelKey] = self;
              }
            }
          } else if (r.type == 'candidate-pair') {
            final crtt = v['currentRoundTripTime'];
            if (crtt is num && (v['nominated'] == true || rtt == null)) {
              rtt = crtt.toDouble();
            }
          } else if (r.type == 'remote-inbound-rtp') {
            final rr = v['roundTripTime'];
            if (rr is num) rtt ??= rr.toDouble();
          }
        }
        if (best > 0) levels[entry.key] = best;
        final q = _computeQuality(
          entry.key,
          packetsLost: packetsLost,
          packetsReceived: packetsReceived,
          jitter: jitter,
          rtt: rtt,
        );
        if (q != null) quality[entry.key] = q;
      } catch (_) {}
    }
    if (levels.isNotEmpty && !_audioLevelCtrl.isClosed) {
      _audioLevelCtrl.add(levels);
    }
    if (quality.isNotEmpty && !_qualityCtrl.isClosed) {
      _qualityCtrl.add(quality);
    }
  }

  /// Maps this interval's RTP stats to a [ConnectionQuality] using per-interval
  /// loss deltas (a connect-time burst shouldn't pin a peer to "poor"). Returns
  /// null until the peer has a usable inbound-rtp sample.
  ConnectionQuality? _computeQuality(
    String peer, {
    int? packetsLost,
    int? packetsReceived,
    double? jitter,
    double? rtt,
  }) {
    if (packetsLost == null || packetsReceived == null) return null;
    final prev = _qualitySamples[peer];
    _qualitySamples[peer] = _QualitySample(
      packetsLost: packetsLost,
      packetsReceived: packetsReceived,
    );
    // First sample → cumulative; thereafter → delta since the last poll.
    final dLost = prev == null ? packetsLost : packetsLost - prev.packetsLost;
    final dRecv = prev == null
        ? packetsReceived
        : packetsReceived - prev.packetsReceived;
    final lost = dLost < 0 ? 0 : dLost;
    final recv = dRecv < 0 ? 0 : dRecv;
    final total = lost + recv;
    final loss = total == 0 ? 0.0 : lost / total;

    if (loss >= _lossPoor || (rtt != null && rtt >= _rttPoor)) {
      return ConnectionQuality.poor;
    }
    if (loss < _lossGood &&
        (rtt == null || rtt < _rttGood) &&
        (jitter == null || jitter < _jitterGood)) {
      return ConnectionQuality.good;
    }
    return ConnectionQuality.fair;
  }
}

/// Snapshot of a peer's cumulative RTP counters from the previous poll, so the
/// next poll can compute per-interval loss.
class _QualitySample {
  _QualitySample({required this.packetsLost, required this.packetsReceived});
  final int packetsLost;
  final int packetsReceived;
}
