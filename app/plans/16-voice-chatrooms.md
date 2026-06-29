# Plan 16 — Voice Chatrooms

Voice chatrooms are Starling's first real-time feature. The core tension is unchanged from the original draft: Starling is async by design (seconds-to-hours latency is fine), but voice needs <200ms round-trip, and Tor (3-5s) is unusable for audio. What *has* changed is the substrate — Plans 11b/11c built the signaling plane this feature was going to build itself, and 11c retired STUN in favor of an IPv6-host-candidate strategy. This plan is rewritten to consume that substrate.

**Prerequisites (all landed):** 07 (HTTP server), 08 (follow flow / key exchange), 09 (LAN sync), 11/11b/11c (Tor + signaling plane), 14 (foreground service).

## What is already built (do not rebuild)

The original "Phase A: signaling infrastructure" is done. Verified in-tree:

- **`/ws/signal` shelf route** with Ed25519 upgrade auth + ±30s replay window (`lib/server/handlers/signaling_handler.dart`).
- **`WsSignalingService`** + **`WebSocketSignalingChannel`** — outbound dial over LAN/Tor (never libp2p), inbound via `handleInbound`, channels pooled by pubkey, `messages` is a **broadcast** stream (`lib/services/signaling/ws_signaling_service.dart`).
- **Sealed envelope** — `wrapSignalingMessage`/`unwrapSignalingMessage` over `EphemeralEncryptedEvent`, pairwise key from `deriveSignalingKey`, ±30s replay window (`lib/services/signaling/signaling_envelope.dart`).
- **`SignalingMessage` + `SignalingMessageType`** — all ten voice types already declared (`roomInvite`, `roomAccept`, `roomDecline`, `roomLeave`, `roomClose`, `offer`, `answer`, `iceCandidate`, `muteStatus`, `speakingStatus`); the model already carries `roomId` and an open `payload` map (`lib/models/signaling_message.dart`).
- **`SignalingDispatcher`** — single owner of `onInboundConnection`; already has labeled (inert) `case` arms for every voice type (`lib/services/signaling/signaling_dispatcher.dart`); start gate is libp2p-independent (`lib/services/lifecycle/lifecycle_manager.dart`).

## Corrected facts (the old draft was stale)

- **Crypto.** Signaling key = `crypto_kdf(BLAKE2b-256(DH(x25519(sk), x25519(pk)) ‖ lo_pk ‖ hi_pk), ctx='starsig0')`, pubkeys **lexicographically sorted** (not `info = my_pk ‖ their_pk`). Feed key uses `ctx='starfk00'`. The old `ctx="starlingsig"` / `salt="starling-signaling-v1"` are wrong.
- **No STUN.** 11c proved STUN/DCUtR unworkable here. WebRTC, however, runs its *own* native ICE agent (separate socket from libp2p), which gathers IPv6 **host** candidates with no server — the WebRTC counterpart of 11c's carrier-v6 bet.
- **Rooms are signaling-plane, not stored `EventKind`s.** `EventKind.isKnown` is hardcoded `1..6`; kinds 10-13 are a documentation reservation only. Room lifecycle rides `SignalingMessage`s; rooms persist solely as local-only call history.

## Architecture

| Channel | Mechanism | Transport | Latency |
|---|---|---|---|
| **Signaling** (invite, SDP, ICE, mute/speaking) | existing `WsSignalingService`, sealed per-recipient | LAN HTTP **or Tor** (never libp2p) | high — Tor fine for setup |
| **Audio** | `flutter_webrtc` `RTCPeerConnection`, DTLS-SRTP | **direct**: LAN host or IPv6 host candidates | <200ms — must be direct |

**The key to WAN voice: signaling rides Tor; media rides direct IPv6.** Setup never needs a direct path (Tor carries the invite/SDP/ICE); only media does, and WebRTC's native ICE gathers the carrier-v6 host candidate for free.

## Connectivity strategy (NAT)

Serverless by default, with an opt-in escape hatch:

1. **LAN host candidates** — same network, <10ms, serverless. The floor.
2. **IPv6 host candidates** — carrier/routable-v6 simultaneous-open over Tor-signaled ICE. The WAN workhorse (~70-85% of pairs, the same envelope 11c hits). No server, no metadata leak.
3. **IPv4 host on permissive NAT** — opportunistic; ICE tries it automatically.
4. **Fail honestly** — if no direct path forms within the ICE timeout, the call cannot connect (no Tor fallback for audio). UI: *"Couldn't connect directly — try the same WiFi, or set up a relay."*

**Hard rules:** `RTCConfiguration.iceServers` defaults to `[]`; never set `iceTransportPolicy: relay`; keep IPv6 ICE enabled. **Opt-in escape hatch:** a Settings field where a user pastes their own `stun:`/`turn:` URLs (e.g. self-hosted coturn) — off by default, labeled as leaving the no-servers guarantee. **No public STUN by default** (ethos violation + IP/timing leak). Where `PeerReachabilityMonitor` already reports `libp2pDirect` reachable for a peer, a v6 voice call is very likely to succeed — surface that as a hint.

## Group topology

**v1: full mesh, hard cap 4.** Each device connects to every other (3 conns/device, Opus @ 64kbps ≈ 192kbps — trivial). Deferred: **v2** participant-as-relay forwarding (~95% group coverage, no servers) and mixer/SFU for 5-8; **v3** relay-as-TURN (the relay has no UDP socket and the spare-device relay sits behind NAT, so only the standalone/VPS tier could ever host it — requires a new clearnet UDP listener + TURN impl + threat-model rework).

## Room model & encryption

- **Invite-only among mutual follows.** Creator picks participants from the mutual-follow list (max 3 invitees). No open/discoverable rooms.
- **Room session key** — creator generates a random 256-bit key, seals it to each participant via the pairwise signaling key. Used as a membership token, **not** the audio key. Audio is E2E via DTLS-SRTP (fingerprints exchanged over the encrypted signaling channel).
- **Lifecycle over signaling** — `roomInvite`/`roomAccept`/`roomDecline`/`roomLeave`/`roomClose` + `offer`/`answer`/`iceCandidate` + `muteStatus`/`speakingStatus`, each a `SignalingMessage` sealed per-recipient with a **fresh timestamp** (the ±30s window forbids cached frames).

## Implementation

### Phase A — Voice signaling layer
- **New `lib/services/voice/room_signaling.dart`** — above `SignalingService`. Per-participant channel open/reuse (`signaling.connect(card)`), fan-out send (re-seal a fresh-timestamped copy per recipient), inbound demux by `roomId`, reconnect-on-drop, dedup by the `SignalingMessage` equality tuple (handles the inbound-via-dispatcher + outbound-direct double path). Subscribes directly to outbound channels (broadcast stream); receives inbound via the dispatcher hook.
- **Modify `signaling_dispatcher.dart`** — add `registerVoiceHandler(void Function(SignalingChannel, SignalingMessage))` / `unregister`; route all ten voice types to it (drop with a log if none registered). Keep `libp2pConnect` as-is.
- **Modify `mock_signaling_service.dart`** — add loopback (paired delivery) so two mock services can drive a full two-peer flow in tests.

### Phase B — Voice service core (WebRTC)
- **New** `lib/services/voice_service.dart` (interface), `lib/services/voice/webrtc_voice_service.dart` (flutter_webrtc: `getUserMedia({audio:true})`, one `RTCPeerConnection` per peer, SDP offer/answer + trickle ICE over `RoomSignaling`, mute via track-enable, speaker route, `audioLevelStream` from stats; `iceServers` default `[]`), `lib/services/voice/ice_config.dart` (default-empty + user-pasted servers), `lib/services/mocks/mock_voice_service.dart`.
- **New** `lib/models/voice_room.dart` — `VoiceRoom`, `VoiceParticipant`, `VoiceRoomState`, `ParticipantConnectionState{connecting,connected,reconnecting,disconnected}`.
- **New** `lib/providers/voice_provider.dart` + binding in `providers/service_providers.dart`; optional `kVoiceEnabled` flag in `utils/feature_flags.dart`.

### Phase C — Room management + storage
- **New** `lib/services/voice/room_manager.dart` — create/invite/join/leave/close, roster, session-key seal/distribution, mutual-follow + 4-cap enforcement.
- **New** drift tables + DAO: `voice_rooms`, `voice_room_participants` (local-only history, 7-day retention) under `lib/services/storage/`.
- **Modify** `storage_service.dart` + `drift_storage_service.dart` (`saveVoiceRoom`, `updateVoiceRoomEnded`, `getRecentVoiceRooms`, `saveVoiceRoomParticipant`, `evictOldVoiceRooms`); `database.dart` schema v7→v8; `retention.dart` 7-day eviction.

### Phase D — UI
- **New** `lib/screens/voice/{room_list,create_room,active_room}_screen.dart`, `lib/widgets/voice/{incoming_invite_sheet,call_overlay,participant_avatar}.dart`. Reuse Plan 04a design system (`Avatar`, `Sheet`, buttons, `SyncDot`).
- **Modify** router + add an entry point; surface the "voice likely to work" hint. _(Post-audit 2026-06-28: the voice hub `RoomListScreen` was promoted from a Friends app-bar icon to a top-level **Rooms** tab — a 4th `StatefulShellBranch` rooted at `/voice`; the active-call screen stays pinned to the root navigator so it covers the tab bar. Screen title is "Rooms".)_

### Phase E — Platform config + hardening
- **Deps** (`pubspec.yaml`): add `flutter_webrtc`, `wakelock_plus`, `permission_handler` (`shelf_web_socket`/`web_socket_channel` already present). No minSdk/iOS-target bumps (Android 26 / iOS 26 clear flutter_webrtc).
- **iOS**: `NSMicrophoneUsageDescription`; append `audio` to `UIBackgroundModes`; `AVAudioSession` `.playAndRecord`/`.voiceChat` at call start. **No CallKit/PushKit** (serverless; consistent with no-push-notifications). Foreground-initiated calls only.
- **Android**: `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `FOREGROUND_SERVICE_MICROPHONE`; parameterize Plan 14's `ForegroundServiceController.serviceTypes` to include `microphone` for call duration (currently hardcoded `dataSync`).
- **Settings**: opt-in custom-ICE field (consumed by `ice_config.dart`).
- **Hardening**: ICE auto-reconnect (~10s), mic-permission-denied UX, `wakelock_plus` during call, battery/thermal warnings, background lifecycle.

## Known limitations (v1)

1. ~15-30% of WAN pairs can't connect (IPv4-only-both-ends / no working v6). No default TURN; UI is honest; user can opt into their own TURN.
2. No voice over Tor (too slow) — Tor is signaling only.
3. 4-person cap (full mesh, no mixer).
4. No background voice on iOS beyond the `audio` mode; no CallKit incoming-while-killed (no VoIP push server).
5. No invite push notifications — app must be open to receive an invite.
6. No recording (by design).

## Verification

- **Unit/integration (`flutter test`):** fan-out seals N fresh-timestamped copies; dispatcher routes each voice type to the registered handler; ±30s replay drops stale frames; mock-loopback two-peer `invite→accept→offer→answer→ice` flow; session-key seal/unseal; 4-cap + mutual-follow gates; storage round-trip + 7-day eviction; migration v7→v8; assert `starsig0`/lex-sorted derivation (no `starlingsig` regressions).
- **Manual, two real devices:** (1) **LAN** — create/invite/join, bidirectional audio, mute, leave/close. (2) **WAN over mobile data** — invite over Tor, audio connects directly over IPv6. (3) **Honest-fail** — IPv4-only both ends → clean "couldn't connect" message, no hang. (4) **Opt-in hatch** — paste a self-hosted `turn:` URL → previously-failing pair connects.
