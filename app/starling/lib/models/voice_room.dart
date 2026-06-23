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

class VoiceParticipant {
  const VoiceParticipant({
    required this.pubkey,
    this.displayName,
    this.isMuted = false,
    this.isSpeaking = false,
    this.connectionState = ParticipantConnectionState.connecting,
  });

  final String pubkey;
  final String? displayName;
  final bool isMuted;
  final bool isSpeaking;
  final ParticipantConnectionState connectionState;

  VoiceParticipant copyWith({
    String? displayName,
    bool? isMuted,
    bool? isSpeaking,
    ParticipantConnectionState? connectionState,
  }) =>
      VoiceParticipant(
        pubkey: pubkey,
        displayName: displayName ?? this.displayName,
        isMuted: isMuted ?? this.isMuted,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        connectionState: connectionState ?? this.connectionState,
      );
}

class VoiceRoom {
  const VoiceRoom({
    required this.id,
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
    this.participants = const [],
    this.invitedPubkeys = const [],
    this.endedAt,
  });

  final String id;
  final String name;
  final String creatorPubkey;
  final int createdAt;
  final List<VoiceParticipant> participants;
  final List<String> invitedPubkeys;
  final int? endedAt;

  bool get isActive => endedAt == null;

  VoiceRoom copyWith({
    String? name,
    List<VoiceParticipant>? participants,
    List<String>? invitedPubkeys,
    int? endedAt,
    bool clearEndedAt = false,
  }) =>
      VoiceRoom(
        id: id,
        name: name ?? this.name,
        creatorPubkey: creatorPubkey,
        createdAt: createdAt,
        participants: participants ?? this.participants,
        invitedPubkeys: invitedPubkeys ?? this.invitedPubkeys,
        endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
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

  VoiceRoomState copyWith({
    VoiceRoom? room,
    bool? localMuted,
    bool? speakerMode,
  }) =>
      VoiceRoomState(
        room: room ?? this.room,
        localMuted: localMuted ?? this.localMuted,
        speakerMode: speakerMode ?? this.speakerMode,
      );
}
