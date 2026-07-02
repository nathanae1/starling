import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/voice_room.dart';
import '../services/storage/keychain_manager.dart';
import '../services/types.dart';
import '../services/voice/ice_config.dart';
import '../services/voice/room_manager.dart';
import '../services/voice/room_signaling.dart';
import '../services/voice/webrtc_voice_service.dart';
import '../services/voice_service.dart';
import '../utils/feature_flags.dart';
import 'service_providers.dart';
import 'sync_provider.dart';

part 'voice_provider.g.dart';

/// flutter_secure_storage key for the opt-in custom ICE servers (Plan 16
/// §Phase E). Stored as the raw multi-line text the user pasted; parsed via
/// [IceConfig.parseServers]. Absent/empty ⇒ serverless (host candidates only).
const String kCustomIceServersKey = 'voice.custom_ice_servers';

/// Voice-room coordination layer over the existing signaling plane.
@Riverpod(keepAlive: true)
RoomSignaling roomSignaling(Ref ref) {
  return RoomSignaling(
    signaling: ref.watch(signalingServiceProvider),
    dispatcher: ref.watch(signalingDispatcherProvider),
    crypto: ref.watch(cryptoServiceProvider),
    clock: ref.watch(clockProvider),
    localPubkeyLookup: () async =>
        (await ref.read(storageServiceProvider).getIdentity())?.pubkey,
    localSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
  );
}

/// The WebRTC media engine. Overridden with a mock in tests.
@Riverpod(keepAlive: true)
VoiceService voiceService(Ref ref) {
  return WebRtcVoiceService(
    iceConfigLookup: () async {
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: kCustomIceServersKey);
      if (raw == null || raw.trim().isEmpty) return const IceConfig();
      return IceConfig(customServers: IceConfig.parseServers(raw));
    },
  );
}

/// Orchestrates room lifecycle + the WebRTC mesh. `start()` is called from
/// [LifecycleManager] so inbound invites are received whenever the app is
/// foregrounded (not only while the voice UI is open).
@Riverpod(keepAlive: true)
RoomManager roomManager(Ref ref) {
  return RoomManager(
    roomSignaling: ref.watch(roomSignalingProvider),
    voice: ref.watch(voiceServiceProvider),
    storage: ref.watch(storageServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    clock: ref.watch(clockProvider),
    localPubkeyLookup: () async =>
        (await ref.read(storageServiceProvider).getIdentity())?.pubkey,
    // Plan 17: a chatroom call authors a durable roomCallStarted record.
    announceCall: kChatroomsEnabled
        ? (roomId, callId) => ref
              .read(roomServiceProvider)
              .announceCall(roomId: roomId, callId: callId)
        : null,
  );
}

/// Live voice-room state for the UI; null when idle. Replays the manager's
/// current state to each subscriber before streaming updates, so a screen
/// mounted after the call started (active room, overlay) renders immediately
/// instead of waiting for the next change.
@riverpod
Stream<VoiceRoomState?> voiceRoomState(Ref ref) async* {
  final manager = ref.watch(roomManagerProvider);
  yield manager.currentState;
  yield* manager.state;
}

/// Inbound room invites awaiting the user's accept/decline.
@riverpod
Stream<VoiceRoom> incomingVoiceInvites(Ref ref) {
  return ref.watch(roomManagerProvider).incomingInvites;
}

/// Room ids whose pending invite was retired unanswered (TTL expiry or the
/// creator closed the call) — the ringing sheet closes on this.
@riverpod
Stream<String> retiredVoiceInvites(Ref ref) {
  return ref.watch(roomManagerProvider).retiredInvites;
}

/// Why the last call ended — drives the non-creator "Call ended" snackbar.
@riverpod
Stream<RoomEndReason> roomEndReason(Ref ref) {
  return ref.watch(roomManagerProvider).roomEnded;
}

/// Recent local call history for the room list. A drift watch stream (not a
/// one-shot read): missed-call rows land invitee-side with NO live-state
/// transition to invalidate on, and a just-finished call must appear
/// without an app restart.
@riverpod
Stream<List<VoiceRoom>> recentVoiceRooms(Ref ref) {
  return ref.watch(storageServiceProvider).watchRecentVoiceRooms(limit: 10);
}

/// Active follows who also follow us — the only contacts invitable to a room
/// (Plan 16 §Room access model).
@riverpod
Future<List<Follow>> mutualFollows(Ref ref) async {
  final storage = ref.watch(storageServiceProvider);
  final follows = await storage.getFollows();
  final out = <Follow>[];
  for (final f in follows) {
    if (f.status == 'active' && await storage.isAcceptedFollower(f.pubkey)) {
      out.add(f);
    }
  }
  return out;
}
