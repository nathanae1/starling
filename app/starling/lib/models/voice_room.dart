/// Plan 16 — voice room model types.
///
/// Voice rooms are coordinated entirely over the signaling plane and persist
/// only as local-only call history (`voice_rooms` table). They are NOT feed
/// events — there is no `EventKind` for them.
library;

/// Hard cap on room size for v1 (full mesh, including the creator).
const int kMaxRoomParticipants = 4;

/// Max invitees the creator may select (room = creator + invitees ≤ cap).
const int kMaxRoomInvitees = kMaxRoomParticipants - 1;

/// Per-participant WebRTC connection state, surfaced to the UI.
enum ParticipantConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

/// Why a participant ended up `disconnected` — the signaling-level outcome,
/// orthogonal to [ParticipantConnectionState] (which the WebRTC engine
/// produces). Drives the tile labels ("No answer" / "Declined" / …) and
/// whether a per-tile Retry makes sense (never for declined/busy/full).
enum ParticipantEndReason {
  /// Invite delivered (as far as we know) but never answered — 60s deadline.
  noAnswer,

  /// A signaling send to them failed outright, or they accepted but the
  /// media path never came up.
  unreachable,
  declined,
  busy,
  roomFull,
}

/// Why the local user's call ended, for the end-of-call UI ("Call ended").
enum RoomEndReason { left, closedByCreator }

/// Coarse per-peer link quality derived from RTP loss / RTT / jitter. Only
/// `fair`/`poor` surface visually (signal bars); `good` shows nothing, and a
/// null quality means "no sample yet" (also drawn as nothing).
enum ConnectionQuality { good, fair, poor }

class VoiceParticipant {
  const VoiceParticipant({
    required this.pubkey,
    this.displayName,
    this.isMuted = false,
    this.isSpeaking = false,
    this.connectionState = ParticipantConnectionState.connecting,
    this.quality,
    this.endReason,
  });

  final String pubkey;
  final String? displayName;
  final bool isMuted;
  final bool isSpeaking;
  final ParticipantConnectionState connectionState;
  final ConnectionQuality? quality;

  /// Set when [connectionState] is `disconnected` and we know why; null for
  /// an engine-level drop with no signaling context ("unreachable").
  final ParticipantEndReason? endReason;

  VoiceParticipant copyWith({
    String? displayName,
    bool? isMuted,
    bool? isSpeaking,
    ParticipantConnectionState? connectionState,
    ConnectionQuality? quality,
    ParticipantEndReason? endReason,
    bool clearEndReason = false,
  }) => VoiceParticipant(
    pubkey: pubkey,
    displayName: displayName ?? this.displayName,
    isMuted: isMuted ?? this.isMuted,
    isSpeaking: isSpeaking ?? this.isSpeaking,
    connectionState: connectionState ?? this.connectionState,
    quality: quality ?? this.quality,
    endReason: clearEndReason ? null : (endReason ?? this.endReason),
  );
}

class VoiceRoom {
  const VoiceRoom({
    required this.id,
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
    this.creatorDisplayName,
    this.participants = const [],
    this.invitedPubkeys = const [],
    this.endedAt,
    this.missed = false,
  });

  final String id;
  final String name;
  final String creatorPubkey;

  /// Resolved locally from the creator's synced profile (never from the
  /// wire — a wire-carried name would be spoofable). Null when no profile
  /// has synced yet.
  final String? creatorDisplayName;
  final int createdAt;
  final List<VoiceParticipant> participants;
  final List<String> invitedPubkeys;
  final int? endedAt;

  /// Invitee-side: this call rang (or would have rung) while we never
  /// answered — invite expiry or busy-auto-decline. History rows only.
  final bool missed;

  bool get isActive => endedAt == null;

  VoiceRoom copyWith({
    String? name,
    String? creatorDisplayName,
    List<VoiceParticipant>? participants,
    List<String>? invitedPubkeys,
    int? endedAt,
    bool clearEndedAt = false,
    bool? missed,
  }) => VoiceRoom(
    id: id,
    name: name ?? this.name,
    creatorPubkey: creatorPubkey,
    creatorDisplayName: creatorDisplayName ?? this.creatorDisplayName,
    createdAt: createdAt,
    participants: participants ?? this.participants,
    invitedPubkeys: invitedPubkeys ?? this.invitedPubkeys,
    endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    missed: missed ?? this.missed,
  );
}

/// The live state of the room the local user is in (or null when idle).
class VoiceRoomState {
  const VoiceRoomState({
    required this.room,
    this.localMuted = false,
    this.speakerMode = false,
  });

  final VoiceRoom room;
  final bool localMuted;
  final bool speakerMode;

  /// True while any participant's transport is mid-reconnect (WebRTC ICE
  /// `disconnected` → [ParticipantConnectionState.reconnecting]). The local
  /// user is seeded `connected`, so this reflects remote peers and drives the
  /// call-wide "Reconnecting…" banner.
  bool get anyReconnecting => room.participants.any(
    (p) => p.connectionState == ParticipantConnectionState.reconnecting,
  );

  /// True while any invitee is still ringing/negotiating. The local user is
  /// seeded `connected`, so this reflects remote peers only — drives the
  /// "Connecting over Tor — this can take a minute" hint.
  bool get anyConnecting => room.participants.any(
    (p) => p.connectionState == ParticipantConnectionState.connecting,
  );

  /// Peers with live media — the honest "N connected" count (the local user
  /// counts as connected).
  int get connectedCount => room.participants
      .where(
        (p) => p.connectionState == ParticipantConnectionState.connected,
      )
      .length;

  VoiceRoomState copyWith({
    VoiceRoom? room,
    bool? localMuted,
    bool? speakerMode,
  }) => VoiceRoomState(
    room: room ?? this.room,
    localMuted: localMuted ?? this.localMuted,
    speakerMode: speakerMode ?? this.speakerMode,
  );
}
