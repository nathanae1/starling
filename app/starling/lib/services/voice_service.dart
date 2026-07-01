import '../models/voice_room.dart';

/// A locally-produced ICE candidate that must be relayed to [peerPubkey] over
/// the signaling plane. [candidate] is the WebRTC candidate as a plain map
/// (`candidate`/`sdpMid`/`sdpMLineIndex`) so it drops straight into a
/// `SignalingMessage.payload`.
class VoiceIceCandidate {
  const VoiceIceCandidate({required this.peerPubkey, required this.candidate});
  final String peerPubkey;
  final Map<String, dynamic> candidate;
}

/// A per-peer connection-state transition from the WebRTC engine.
class VoicePeerState {
  const VoicePeerState({required this.peerPubkey, required this.state});
  final String peerPubkey;
  final ParticipantConnectionState state;
}

/// The WebRTC media engine for voice rooms (Plan 16 §Phase B).
///
/// Deliberately WebRTC-agnostic at the boundary: SDP and ICE cross as plain
/// maps so [room_manager] can ferry them over the signaling plane untouched
/// and so the mock needs no platform bindings. One [VoiceService] drives the
/// whole mesh — a peer connection per remote participant. DTLS-SRTP provides
/// the E2E audio encryption; this service never sees a media key.
abstract class VoiceService {
  /// One-time setup (audio session config etc.). Safe to call repeatedly.
  Future<void> init();

  /// Acquire the local microphone and begin a session for [roomId]. Until
  /// this resolves, offer/answer calls have no local media to attach.
  Future<void> startSession(String roomId);

  /// Create (and locally set) an SDP offer for [peerPubkey], creating the
  /// peer connection if needed. Returned map = `{sdp, type}`.
  Future<Map<String, dynamic>> createOffer(String peerPubkey);

  /// Apply [remoteOffer], create + locally set an answer, and return it.
  Future<Map<String, dynamic>> createAnswer(
    String peerPubkey,
    Map<String, dynamic> remoteOffer,
  );

  /// Apply the remote [answer] to the offer we previously sent [peerPubkey].
  Future<void> setRemoteAnswer(String peerPubkey, Map<String, dynamic> answer);

  /// Add a remote ICE [candidate] received over signaling.
  Future<void> addRemoteIceCandidate(
    String peerPubkey,
    Map<String, dynamic> candidate,
  );

  /// Local ICE candidates to relay to peers via signaling.
  Stream<VoiceIceCandidate> get localIceCandidates;

  /// Per-peer connection-state transitions.
  Stream<VoicePeerState> get peerStates;

  /// `pubkey -> normalized 0..1 audio level` snapshots (speaking detection),
  /// emitted on a low-frequency poll. Best-effort.
  Stream<Map<String, double>> get audioLevels;

  /// `pubkey -> coarse link quality` snapshots, derived from the same
  /// low-frequency stats poll as [audioLevels]. Best-effort; a peer is absent
  /// from the map until it has a usable RTP sample.
  Stream<Map<String, ConnectionQuality>> get connectionQuality;

  Future<void> setMicMuted(bool muted);
  Future<void> setSpeakerMode(bool speaker);

  /// Tear down the peer connection for one participant (they left).
  Future<void> removePeer(String peerPubkey);

  /// End the session: close every peer connection and release the mic.
  Future<void> endSession();

  bool get micMuted;
  bool get speakerMode;
}
