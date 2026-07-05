# Plan 20 — Relay-hosted voice (SFU)

Plan 16 shipped voice as a serverless full mesh, hard-capped at 4 because every phone must upload N-1 audio streams and hold N-1 peer connections. Plan 17 made rooms durable with one live call at a time, still on the mesh. This plan adds the next rung of the self-hosting gradient: **when a room's creator has a paired relay, live calls in that creator's rooms are hosted on the relay as an SFU** — every participant sends one stream up, the relay fans out the rest — raising the call cap well past 4 and collapsing the N² pairwise-connectivity problem (15-30% WAN pair failure) into a single question: *can each participant reach the relay?*

The relay stays zero-knowledge: it forwards **end-to-end encrypted audio frames it cannot decrypt**, and it never learns participant identities — only blinded room tokens, ephemeral ids, and (unavoidably, for latency) participant IPs.

**Prerequisites (all landed):** 15 (relay + pairing + owner-signed push), 16 (voice mesh, signaling plane), 17 (durable rooms, room key lifecycle, `startRoomCall`).

## Locked product decisions

| Decision | Choice |
|---|---|
| Topology trigger | A call is SFU-hosted iff the **room creator** has a paired relay with voice hosting enabled. Chosen at call start; **no mid-call topology switch**. |
| Call cap (SFU) | Relay-configured `voice_max_participants`, **default 12**, config ceiling 24. Mesh cap stays 4 (`kMaxRoomParticipants` untouched). |
| Admission authority | The **relay** is the single admission gate in SFU mode (join order, cap). No distributed cap race like the mesh's accept-glare. |
| Media privacy | **Mandatory E2EE audio frames** (flutter_webrtc `FrameCryptor`, key derived from the per-call `session_key`). The SFU forwards ciphertext. Non-negotiable — zero-knowledge is a design principle, not a feature flag. |
| Identity privacy | Relay never sees member pubkeys. Rooms are registered as **blinded token hashes**; participants join with the token preimage and a relay-assigned ephemeral id. |
| Silence suppression | **Opus DTX** (`usedtx=1`) enabled on all voice paths — SFU *and* the Plan 16 mesh. No custom VAD pipeline in v1 (the codec's built-in DTX is the VAD). |
| Fallback | SFU unavailable/unreachable at call start → fall back to the Plan 16 mesh (cap 4), honestly labeled. Per-participant ICE failure to the SFU → that participant fails cleanly (same honest-fail UX as mesh). |
| Transport posture | The relay gains its **first clearnet socket**: one UDP port for media. Off by default (`[voice] enabled = false`); signaling stays on the per-Owner onion. |

## Architecture

| Plane | Carries | Transport | Latency need |
|---|---|---|---|
| Durable room (text, membership, room key, **voice token**) | Plan 17 events + sealed `room-key` items | outbound queue, Tor/LAN | async |
| Call announce + roster gossip (invite/accept/mute, `sfu_id` mapping, `session_key`) | Plan 16 `SignalingMessage`s | `WsSignalingService`, Tor/LAN | seconds — fine |
| SFU session signaling (join, SDP, ICE, peer-joined/left) | new CBOR WS frames | **WS to the creator's relay onion** (Tor) | seconds — fine |
| Audio | one `RTCPeerConnection` per participant → SFU, DTLS-SRTP + E2EE frames | **direct UDP to the relay** (LAN / IPv6 / public v4) | <200ms — must be direct |

```
   phone A ──1 up──▶ ┌──────────────┐ ──▶ N-1 down ──▶ phone B
   phone C ──1 up──▶ │ relay SFU    │ ──▶ …
   phone D ──1 up──▶ │ (forwarder,  │      RTP payloads are FrameCryptor
                     │  no decrypt) │      ciphertext; DTLS-SRTP is
                     └──────────────┘      hop-by-hop, frames are E2E
```

Setup rides Tor (invite over the signaling plane, SDP/ICE over the relay-onion WS); only media needs a direct path — and only to the relay, which is a stable server the owner controls (port-forwardable, usually with stable v6), a far better connectivity bet than N² phone pairs.

## Bandwidth & DTX (why 12 works, and the answer to "should we add voice detection?")

Opus VoIP ≈ 32 kbps + RTP/SRTP/UDP overhead ≈ **~50 kbps on-wire per talking stream** (20 ms ptime). With DTX, a silent participant drops to comfort-noise refreshes — **~1-2 kbps**.

| N=12 | worst case (all talking) | typical (2 active speakers, DTX) |
|---|---|---|
| relay egress | 12×11×50k ≈ **6.6 Mbps** | ≈ 12×2×50k ≈ **1.2 Mbps** |
| relay ingress | ≈ 0.6 Mbps | ≈ 0.15 Mbps |
| phone up / down | 50 kbps / 550 kbps | ≤50 kbps / ~100 kbps |

Worst case fits a mediocre home upload; typical case is trivial. DTX is why the cap is comfortable — so yes, silence suppression is in, and the right mechanism is **Opus DTX, not a hand-rolled VAD**: the encoder already runs voice-activity detection internally, handles word-onset clipping better than a track-mute gate, and needs only `usedtx=1` in the SDP fmtp (a munge before `setLocalDescription`, applied in one shared helper used by both mesh and SFU paths). It also cuts phone battery and helps the existing mesh for free. Client-side hard gating (mute track under a threshold) is deferred — the UI speaking indicator already computes levels (`RoomManager.speakingThreshold`), and DTX captures ~all of the win. Honest tradeoff: DTX makes speech on/off rhythm visible to on-path observers (packet timing) — inherent to any real-time media that isn't constant-bitrate padded, and the relay could infer the same from SRTP packet sizes anyway; noted in the threat model below.

## Privacy & zero-knowledge design

**What the relay learns in a call (be honest):** that a call is live on one of its owner's blinded room slots, participant count, join/leave times, participant **IP addresses** (media is direct UDP — unavoidable), and speech-activity rhythm (packet timing). **What it cannot learn:** audio content (E2EE frames), participant identities (no pubkeys on the voice path; WS signaling arrives over Tor), room names/membership, or any linkage to feed content. This is a real, new metadata exposure for *participants* (today only the owner trusts their relay; now their friends' IPs touch it) — surfaced in UI copy: *"Call hosted on <creator>'s relay."*

- **Voice token.** `RoomService` mints a random 32-byte `voiceToken` per room, stored in a new `rooms.voiceToken` column, sealed to members **alongside the room key** (extend the Plan 17 `room-key` item payload), and **rotated exactly when the room key rotates** (member remove — extend `room_key_rotation_service.dart`). The relay stores only `BLAKE2b-256(voiceToken)`.
- **Slot registry.** The owner's phone pushes the owner-signed full slot set — `POST /voice/rooms`, CBOR `{slots:[{token_hash, max_participants?}]}` — on room create/membership change/pair, **best-effort + reconcile** (the Plan 15 push posture; reconcile diff via slot list in `/status`). Replace-the-set semantics: one transaction, delete+insert.
- **Join.** Participant opens `GET /ws/voice` on the creator's relay onion (address from the creator's stored Connection Card; echoed in the invite payload as fallback), first frame presents the token preimage. Hash match → admitted with a relay-assigned ephemeral `sfu_id`; no Ed25519 anywhere on this path. Anonymous rate-limit bucket (reuse `rate_limit.rs`).
- **E2EE frames.** `frame_key = BLAKE2b-256(session_key ‖ "starling-voice-frame-v1")` where `session_key` is the existing per-call key already minted and sealed pairwise in `roomInvite` (`room_manager.dart`). Loaded into a shared-key `KeyProvider`; a `FrameCryptor` attaches to every RTPSender/Receiver on the SFU connection. The relay forwards opaque payloads; RTP headers stay plaintext for routing. A stolen `voiceToken` (relay compromise) admits a silent listener to *ciphertext* only — and it surfaces in every client's UI as an **unmapped participant** (see mapping below), which the UI flags.
- **Identity mapping (client-side only).** Each participant announces its `sfu_id` in its `roomAccept` payload over the existing signaling plane (present members already re-gossip accepts, so late joiners converge). Clients join `sfu_id → pubkey` for avatars/speaking UI; the relay never holds the mapping. Tracks with no mapping render as "Unknown participant" + warning.
- **No mid-call rekey.** Token rotation applies at next join; a member removed mid-call stays until the call ends (mesh has the same property — no kick in v1).

## Relay-side design (Rust)

**New crate `relay/crates/starling-relay-voice`** — the SFU. Recommendation: **str0m** (sans-IO WebRTC built for SFU use: ICE-Lite, single-UDP-socket demux by ufrag, DTLS-SRTP, RTP forwarding; we drive it from tokio with one socket task). ~~Phase A includes a build spike: str0m's DTLS backend (openssl) must survive the `cargo-zigbuild` musl/distroless pipeline; if vendored-openssl fights back, fall back to `webrtc-rs`.~~ **Spike outcome (2026-07-03): GO on str0m 0.21** — it ships a pure-Rust `rust-crypto` DTLS backend (`default-features = false, features = ["rust-crypto"]`; the default `aws-lc-rs` needs cmake and is avoided). Handshake + RTP verified functionally; both musl targets build via cargo-zigbuild and the exact Docker/distroless CI path; no movement of the arti/rusqlite pins. The crate exposes: `VoiceServer::start(cfg) -> VoiceHandle` (owns the UDP socket), `VoiceHandle::register_slots(owner_pubkey, slots)`, `VoiceHandle::open_session(owner)` (channel-based session API the WS adapter drives), plus per-call state (participants, cap, idle reap when empty >60s). Pure forwarder: no decode, no mixing, no audio-level inspection. Implementation note: sessions adopt each SDP m-line's auto-created `StreamTx` (str0m keys streams by SSRC and resolves by-mid lookups in hash order — declaring a second stream on a negotiated mid makes sending nondeterministic).

- **ICE:** relay runs ICE-Lite with host candidates only: auto-detected interface addrs (LAN + global v6 — covers the VPS public-v4 case) plus `voice_advertised_addrs` for the port-forwarded-home-NAT case. Sent to clients in `join_ack`; phones do full ICE (their `iceServers` stay `[]`).
- **WS protocol** (CBOR frames on `/ws/voice`, served on the per-Owner router behind the onion — Arti's reverse proxy is a plain TCP proxy, long-lived WS is fine): `join{token}`, `join_ack{sfu_id, candidates, cap, participants}`, `offer/answer{sdp}`, `ice{candidate}`, `peer_joined{sfu_id, mid}` / `peer_left{sfu_id}`, `full`, `bye`, `error{code∈bad_token|busy|protocol|internal}`. The client offers exactly once (its sendonly mic); every later SDP change is a serialized server re-offer (an answer can't add m-lines). *(Amended in B: the handler lives in `starling-relay-voice` and the supervisor merges it into the per-Owner router — `starling-relay-http` must not depend on the voice crate or its DTLS-SRTP AEAD tree would gut the zero-knowledge dep walk. URL surface unchanged. Frame types live in `starling-wire/src/voice.rs`.)*
- **Storage:** migration adds `voice_slots(pubkey BLOB NOT NULL REFERENCES paired_owners(pubkey) ON DELETE CASCADE, token_hash BLOB NOT NULL, max_participants INTEGER, updated_at INTEGER NOT NULL, PRIMARY KEY(pubkey, token_hash))`. Live call state is memory-only.
- **API additions** (per-Owner onion): `POST /voice/rooms` (owner-sig via the existing `verify_owner_request`, `middleware.rs:26`), `GET /ws/voice` (token-authed upgrade). `/status` gains `voice:{enabled, max_participants, slot_count}` so the phone can detect capability at pair/reconcile time. *(Amended in B: `voice` is **always present** — a disabled relay reports `enabled:false` — so Phase C capability detection is a plain field read.)*
- **Config** (`config.rs`, `deny_unknown_fields` — new `[voice]` table): `enabled=false`, `udp_port=0`, `advertised_addrs=[]`, `max_participants=12` (validated 2..=24), `max_concurrent_calls=4`. Docker/README note: `-p <port>:<port>/udp`. *(Amended in B: `udp_port=0` means OS-assigned each boot — fine for LAN/v6 testing, useless behind a port-forward; the relay warns at startup.)*
- **Glue:** `main.rs` starts one shared `VoiceServer` when enabled; `supervisor.rs` passes the handle into each owner's router ctx; slot registry loaded at boot and updated by the push handler. Unpair drops the owner's slots (FK cascade) and ends live calls.
- **Zero-knowledge enforcement:** ~~extend `tests/zero_knowledge.rs` to walk `starling-relay-voice`'s deps too~~ *(Amended in B: impossible as written — DTLS-SRTP legitimately links AEAD crates, which is hop transport the SFU terminates by design. Implemented instead: a **codec denylist** walk over `starling-relay-voice` AND the shipped `starling-relay` binary — no Opus/audio-decode machinery anywhere — plus a **boundary test** keeping the WebRTC stack out of the store-and-forward crates so the AEAD walk stays meaningful)*; the loopback test asserting forwarded RTP payloads are bit-identical in/out (no transcode path exists) is in `starling-relay-voice/tests/loopback.rs`.
- **Admin UI:** aggregate only — per-owner "voice: on, N active calls". No per-participant attribution (consistent with the existing dashboard rule).
- **starling-wire:** new CBOR types (`VoiceSlotPush`) + shared vectors in `app/starling/test/vectors/index.json` (Dart-encode → Rust-decode, and the frame-key derivation vector pinned on the Dart side).

## Phone-side design (Dart)

- **Capability discovery:** at pair + reconcile, read `/status.voice`; persist `voiceEnabled`/`voiceMaxParticipants` on `paired_relay`. When it flips, re-sign the Card adding capability **`relay-voice-v1`** (`connection_card.dart` capabilities list) and fan out via the existing Plan 13 machinery (`relay_pairing_service.dart` `_distributeCard`). Members detect SFU-capable rooms from the creator's stored card: `relay-voice-v1` + an `Endpoint(type:'relay')`.
- **Mode selection** (`room_manager.dart`): `startRoomCall` checks the room creator's card. SFU-capable → open the relay WS, `join`; on success send `roomInvite` with `payload: {mode:'sfu', relay_onion, cap, session_key}`. On failure (unreachable, `full`, no slot) → today's mesh invite unchanged. `acceptInvite` branches on `mode`. Cap in SFU mode comes from `join_ack`, not `kMaxRoomParticipants`.
- **New `lib/services/voice/sfu_call_session.dart`:** one `RTCPeerConnection` to the SFU; WS signaling client over Tor (reuse the existing Tor-SOCKS WS dial pattern from `ws_signaling_service.dart`); renegotiation on `peer_joined/left`; `FrameCryptor` per sender/receiver from a shared `KeyProvider` (new `lib/services/voice/frame_crypto.dart` — derivation + setup); emits the **same stream shapes as `VoiceService`** (`peerStates`, `audioLevels` keyed by pubkey via the `sfu_id` map, `connectionQuality`) so `active_room_screen.dart`, `CallOverlay`, and the providers are reused with minimal change. Mesh `WebRtcVoiceService` untouched except the shared DTX munge helper.
- **DTX:** `lib/services/voice/sdp_munge.dart` — add `usedtx=1` to the Opus fmtp on local SDP in both `webrtc_voice_service.dart` and `sfu_call_session.dart`.
- **Token plumbing:** `rooms` table gains `voiceToken` (schema v13→v14); `room_service.dart` mints + seals it with the room key; `room_key_rotation_service.dart` rotates it; `room-key` ingest (`room_ingest.dart`) stores it.
- **Roster push:** extend `relay_push_service.dart` (`POST /voice/rooms` with the existing `ownerRequestDigest` headers) and `relay_push_coordinator.dart` (push on room create/membership change; reconcile diff on the existing tick; never throws into callers).
- **UI:** participant grid beyond 4 in `active_room_screen.dart`; "Hosted on <name>'s relay" line + privacy copy in the invite sheet and active call; unmapped-participant warning; owner-side Settings row under the relay section ("Voice hosting: on/off — configured on the relay") reading `/status`; honest-fail copy gains the SFU case (*"Couldn't reach <name>'s relay — trying direct…"*).

## Call flow (SFU mode)

1. Any member taps "Start call". Phone sees creator's card is `relay-voice-v1` → WS `join` to the relay onion (token preimage) → `join_ack{sfu_id, candidates, cap}`.
2. Starter authors durable `roomCallStarted` (Plan 17, unchanged) and fans `roomInvite{mode:'sfu', relay_onion, cap, session_key}` + its `sfu_id` via `roomAccept` gossip.
3. Each joiner: WS `join` → SDP offer (sendonly mic + recvonly) → SFU answer → ICE to the relay's candidates → DTLS-SRTP up, FrameCryptor on.
4. SFU re-offers existing participants on each join/leave; clients map new mids to pubkeys via gossip.
5. Leave = WS `bye` + `roomLeave` gossip; call ends when empty (relay reaps after 60s idle). Mesh semantics for close/decline/mute unchanged.

## Phasing

- **A — SFU core spike + crate:** ✅ **landed 2026-07-04.** str0m 0.21 spike = GO (pure-Rust `rust-crypto` DTLS backend; both musl targets + Docker/distroless pipeline verified); `starling-relay-voice` with loopback tests over real UDP (byte-identical forwarding, cap→full, idle reap, slot replace/rotate, bad token, drop_owner ends calls, max_concurrent_calls→busy, 3-way renegotiation + leave).
- **B — Relay integration:** ✅ **landed 2026-07-04.** `[voice]` config, `voice_slots` migration (relay schema v4), `POST /voice/rooms` + `/ws/voice` routes, `/status.voice`, supervisor/main glue, zero-knowledge codec+boundary guards, admin aggregate row, wire vectors (`voice_slot_push`, `voice_slot_receipt`, `status_json`, `http.endpoints.{voice_rooms,ws_voice}`).
- **C — Phone token + roster plumbing:** `rooms.voiceToken` (v14), mint/seal/rotate, push + reconcile, `paired_relay` voice columns, `relay-voice-v1` card capability + fanout.
- **D — Phone SFU call path:** `sfu_call_session.dart`, `frame_crypto.dart`, WS-over-Tor client, `room_manager.dart` mode selection + fallback, `sdp_munge.dart` DTX for both paths.
- **E — UI + polish:** grid, hosted-on copy, unmapped-participant warning, settings surface, honest-fail strings.
- **F — Verification** (matrix below).

## Risks / open questions

1. ~~**str0m DTLS backend vs musl/zigbuild**~~ — **resolved (Phase A spike):** str0m 0.21's pure-Rust `rust-crypto` backend passes the full pipeline; openssl never entered the tree.
2. **`FrameCryptor` maturity on flutter_webrtc 1.5.0** (iOS + Android, audio) — used in production by LiveKit-family apps, but verify early in Phase D on both platforms; it is the zero-knowledge linchpin, so a failure here blocks SFU mode entirely rather than shipping without E2EE.
3. **Relay WAN reachability** (CGNAT, no v6, no port-forward) — voice hosting silently unreachable from WAN. v1: document + admin-UI hint showing advertised candidates; a self-probe ("can I reach my own UDP port from outside?") needs an external vantage point and is deferred.
4. **Renegotiation churn** on rapid join/leave — serialized per call; str0m keeps per-session state small. Watch in Phase F load test (24 joins/leaves scripted).
5. **Session-key handoff for late joiners** mirrors mesh (starter validates/echoes) — if the starter leaves, late joiners can't get the key. Existing mesh limitation, inherited; fix (any-present-member reseal) deferred.
6. **Tor WS stability** for hour-long calls — signaling only (media unaffected); auto-reconnect + `join` re-attach with the same `sfu_id` within a grace window. *(Phase B note: the relay currently treats WS-close as leave; the re-attach grace window is client-driven and lands with Phase D.)*

## Known limitations (v1)

1. SFU calls require the creator's relay to be UDP-reachable by every participant; failures fall back to mesh (cap 4) at start, or per-participant honest-fail.
2. Participants' IPs and speech-activity timing are visible to the creator's relay (not identities, not audio).
3. No mid-call rekey, kick, or topology switch; token rotation applies at next join.
4. Audio only; no recording (by design).
5. Owner cannot cap per-identity (identities are blinded); caps are per-slot totals.

## Verification

- **Rust:** loopback SFU tests (forwarding byte-identity, cap → `full`, idle reap, slot replace/rotate semantics, unpair cascade ends calls); token-hash auth (wrong preimage → `error`, rate-limit bucket); zero-knowledge dep walk incl. voice crate; wire vectors for `VoiceSlotPush`.
- **Dart:** token mint/seal/rotate alongside room key (removed member's old token rejected by hash mismatch); roster push/reconcile diff; `SfuCallSession` against a mock WS (join→offer/answer→peer_joined re-offer→bye); frame-key derivation pinned vector; mode selection (capability present → SFU, join failure → mesh fallback invite); DTX munge idempotent + present in both paths' SDP; migration v13→v14.
- **Manual matrix:** (1) **LAN relay, 6 phones** — 6-way call (impossible on mesh), audio all-ways, join/leave churn. (2) **WAN** — participant on mobile data reaches a port-forwarded/v6 relay; call connects; Tor signaling survives a network blip. (3) **Zero-knowledge spot-check** — tcpdump on the relay: SRTP payloads; with a deliberately wrong frame key the client renders silence/garbage (proves E2EE is load-bearing). (4) **Fallback** — UDP port blocked → starter lands on mesh with honest copy. (5) **DTX** — packet capture shows ~1-2 pkts/s from a silent participant, both mesh and SFU. (6) **Rotation** — remove a member, confirm their old token can no longer join the next call.

## Spec amendment (`relay/plans/relay-spec.md`, apply when code lands)

Add a **Voice (SFU)** section: the two new API rows (`POST /voice/rooms` owner-sig; `GET /ws/voice` token-authed), the `[voice]` config block, the `voice_slots` schema + cascade, the clearnet-UDP posture change (off by default), and Security considerations additions: blinded slots, E2EE frames (relay forwards ciphertext), the participant-IP/timing metadata exposure, and the stolen-token → ciphertext-only-listener analysis.

## Critical files

- `relay/crates/starling-relay-http/src/lib.rs:86` (`owner_router` — mount voice routes), `middleware.rs:26` (owner-sig reuse), `rate_limit.rs`
- `relay/crates/starling-relay/src/{config.rs, main.rs, supervisor.rs}` — `[voice]` config + shared `VoiceServer` glue
- `app/starling/lib/services/voice/room_manager.dart` — mode selection; `session_key` already minted/sealed here (line ~215/281)
- `app/starling/lib/services/{room_service.dart, room_key_rotation_service.dart}` — voiceToken lifecycle rides the room key
- `app/starling/lib/services/{relay_push_service.dart, relay_push_coordinator.dart}` — owner-signed slot push + reconcile posture
- `app/starling/lib/services/storage/tables/rooms_table.dart` + `database.dart` (v13→v14)
- `app/starling/lib/models/connection_card.dart` — `relay-voice-v1` capability
- `app/starling/lib/services/voice/webrtc_voice_service.dart` — shared DTX munge; mesh otherwise untouched
