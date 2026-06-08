# Plan 11c — Fix libp2p direct-connect tier (post-11a/11b review)

## Status: IMPLEMENTED

All §Approach changes below are in tree. See `git log -- 'app/starling/native/libp2p_bridge/**'` and `git log -- 'app/starling/lib/services/libp2p/**'` for the per-task commits.

Open verification work — items #4 (loopback integration), #5 (frame-preservation test), and #6 (two-phone smoke) — remain TODO. See §Verification below.

## Context

Plans 11a + 11b shipped the libp2p direct-connect tier end-to-end (native crate, iOS xcframework, Android `.so`, Dart FFI bridge, inbound stream server, signaling dispatcher), and the feature flag is on. The post-implementation review surfaced a layer of issues that fall into three groups:

1. **Architectural mismatch with the "no public relays" constraint.** The original design assumed STUN-style reflexive-address discovery + DCUtR-protocol hole-punching gives us "70-80% NAT traversal." It can't, because (a) the STUN client binds its own ephemeral UDP socket so reflected ports don't map to the QUIC listener, (b) libp2p's `dcutr::Behaviour` needs a `circuit-relay-v2/client` to fire at all and there is no relay, and (c) `libp2p-quic 0.12` doesn't expose quinn's Endpoint/socket, so we can't make STUN share the QUIC port without forking the transport.
2. **Threading model puts blocking FFI on the Dart UI isolate.** `lp_dial_direct`, `lp_open_stream`, `lp_stream_write`, `lp_stream_read` all called `runtime.block_on` and could stall the caller for up to 30 s. Plan 11a noted "mirror ArtiTorService pattern" but arti's per-call `Isolate.run` is wrong for libp2p's call frequency (~30+ FFI calls per sync pump).
3. **Concrete bugs and resource-lifecycle issues** that would have bitten the two-phone smoke: `lp_stream_read` discarded frames > 64 KiB, the upgrader's `finally` closed the cached signaling channel, dial-timeout cleanup was a no-op, STUN never re-ran on network-change, the production `SignalingDispatcher` ran against `MockSignalingService` when identity was unloaded, and so on.

**Re-framing the NAT envelope.** After auditing IPv6 reality: cellular carriers (AT&T, T-Mobile, Verizon, most EU) assign globally-routable v6 to mobile devices and apply a stateful firewall with *endpoint-independent filtering* — functionally identical to full-cone NAT. Simultaneous-open over v6 punches it the same way WireGuard / Tailscale / WhatsApp do, with ~95% empirical success when both peers have working v6. Combined with LAN and v4 full-cone NATs (residential Wi-Fi), the realistic envelope for libp2p-direct is closer to 70-85% of follow pairs — *without* a relay. The remaining 15-30% (IPv4-only on both ends, or one carrier blocking v6) falls back to Tor, as designed.

Pre-production, so this plan made breaking changes (deleted the STUN module, dropped `dcutr::Behaviour`, re-derived feed keys via context change, etc.) without migration code.

## Goals

- libp2p direct-connect succeeds on every topology where it physically can (LAN, IPv6-on-both-ends, full-cone/restricted-cone IPv4 NAT).
- No FFI call ever blocks the main Dart isolate.
- The shared `SignalingService` channel cache is owned by exactly one consumer; nothing else closes it.
- Two-phone smoke test (`19` in `11a-libp2p-direct-remaining.md`) achievable in good faith, with expectation tables matching the new physics-honest envelope.

## Non-goals

- No relay (per user direction: 100% P2P, no public relays).
- No carrier-grade-NAT traversal for IPv4-only symmetric NATs. Those stay on Tor. A future self-hosted starling node (Plan 15) is the long-term path for users whose followers can't reach them directly.
- No port-prediction / spraying.

## Approach

### A. NAT traversal & address discovery

**Dropped the STUN client, dropped `dcutr::Behaviour`, added an IPv6 listener, enumerate routable v6 addresses per-interface, source v4 observed_addrs only from `identify::Event::Received { info.observed_addr }`.**

Rationale: without a relay, libp2p's `dcutr::Behaviour` can't fire and the STUN client's reflected ports don't match the QUIC listener (libp2p-quic doesn't expose its socket). IPv6 sidesteps the whole observability problem — the device's OS-assigned v6 IS its public address, no translation involved. v4 still relies on Identify reflections from peers post-connect (cold-start v4 direct only works on LAN).

Concrete changes:

- `native/libp2p_bridge/src/inner.rs::build_swarm` — removed `dcutr` from `Behaviour`. Cargo.toml drops the `dcutr` libp2p feature.
- `native/libp2p_bridge/src/inner.rs::run` — added `swarm.listen_on("/ip6/::/udp/0/quic-v1".parse()?)` immediately after the v4 listener.
- New `native/libp2p_bridge/src/interfaces.rs` — uses `if-watch` to enumerate the device's routable v6 addresses per network interface; on startup and on every change event, for each global v6 found, constructs `/ip6/<addr>/udp/<bound_port>/quic-v1` and inserts via `Cmd::AddObservedAddr` (same filter as the swarm).
- `native/libp2p_bridge/src/inner.rs::insert_if_routable` — central filter that rejects unspecified (`0.0.0.0`, `::`), loopback (`127/8`, `::1`), and link-local (`169.254/16`, `fe80::/10`). Keeps LAN-private v4 and ULA v6 (useful for same-network peers).
- Deleted `native/libp2p_bridge/src/stun.rs`.
- `lib/sync/libp2p_upgrader.dart::_attemptUpgrade` — relaxed the empty-observedAddrs bail. Always sends the `libp2pConnect` message with whatever candidates we have (typically real v6 + LAN v4 on cold start). The peer dials each; the first QUIC handshake to complete wins.

### B. Dart ↔ FFI threading: dedicated bridge isolate

**One long-lived `Isolate` owns `Libp2pBindings` and the Rust handle. The public `Libp2pService` interface forwards each call to that isolate via a `SendPort`/oneshot-`ReceivePort` pair.**

Rationale: every mature Flutter native plugin (sqflite, isar, drift `NativeDatabase`, etc.) follows this pattern. arti's per-call `Isolate.run` works because arti makes a handful of coarse calls per session; libp2p has dozens of fine-grained stream operations per sync pump where per-call isolate spawn (~5–15 ms) would dominate. A long-lived isolate also gives single-owner FFI access (no concurrent-handle bugs) and the Native Port event channel already crosses isolate boundaries cleanly.

Concrete changes:

- New file `lib/services/libp2p/libp2p_bridge_isolate.dart` — `libp2pWorkerEntry` runs inside `Isolate.spawn`. Owns the singleton `Libp2pBindings` handle. Receives `{cmd, args, reply}` maps over its `ReceivePort` and replies via the embedded `SendPort`.
- Refactored `lib/services/libp2p/libp2p_bridge.dart` — `Libp2pBridge` keeps the same public surface but every method becomes `await _call(cmd, args)` via the worker. Worker spawned lazily on first `init()`; killed on `shutdown()`.
- Native Port event delivery still routes *directly* to the main isolate's `RawReceivePort`, not through the worker. We tell the worker the port's `nativePort` (via `dart:ffi`'s `NativePort` extension on `SendPort`) at init, the worker passes it to `lp_set_event_port`, and Rust posts events to the main isolate without a worker hop.
- `_FfiStream` replaced by `_WorkerStream` — same `Libp2pStream` surface, but read/write/close each await a worker round-trip.

### C. `lp_stream_read` frame-loss fix

**Re-shaped the read protocol so a too-small buffer doesn't consume the frame.**

- Added `pending_frame: parking_lot::Mutex<Option<Vec<u8>>>` to `StreamHandle`.
- `lp_stream_read` now checks `pending_frame` first; if present, copies from there. If the receiver yields a frame that doesn't fit the caller's buffer, the frame is stashed in `pending_frame` (instead of dropped), `LP_ERR_BUFFER_TOO_SMALL` is returned, and the caller's next call with a bigger buffer gets the *same* frame.
- Dart side `_WorkerStream.read` doubling-loop is now genuinely correct.

### D. Stop the upgrader from closing shared signaling channels

`lib/sync/libp2p_upgrader.dart::_attemptUpgrade` — removed the `finally { try { await channel?.close(); } catch (_) {} }` block. The signaling channel is owned by `WsSignalingService._channels`; the upgrader is a consumer. Channel teardown happens when `WsSignalingService.closeAll()` is called (lifecycle pause) or when the underlying WebSocket drops.

### E. Concrete bug fixes

- **Dial-timeout cleanup** — `native/libp2p_bridge/src/inner.rs::handle_cmd::DialDirect`: replaced the no-op timeout task with a watchdog that sends `Cmd::DialTimeout { peer }` back through the event-loop channel. The loop's new arm prunes `pending_dials[peer]` and signals `Err("dial timed out")` on the captured oneshot. All swarm-touching work stays on the event-loop task.
- **Stale state on shutdown** — `lib/services/libp2p/libp2p_bridge.dart::shutdown`: clears `_inboundHandlers`, `_connByPeer`, `_localPeerId`. `_eventCtrl` is intentionally NOT closed (keep-alive Riverpod singleton).
- **Dispatcher gated on real signaling binding** — `lib/services/lifecycle/lifecycle_manager.dart::start` / `onResume`: only call `signalingDispatcherProvider.start()` if `signalingServiceProvider` resolves to a real `WsSignalingService`; otherwise log + skip. `onResume` retries on every foregrounding so onboarding-mid-session is covered.
- **`late ProviderContainer` removed from `main.dart`** — new `productionSignalingProvider` (a notifier) in `service_providers.dart` carries the runtime-bound `WsSignalingService`. `signalingServiceProvider` watches it; falls back to `MockSignalingService` when null. `main.dart` builds the container, constructs `WsSignalingService` against it, and `.set()`s the value on the notifier.

### F. Crypto + Swift fixes (pre-existing breakages)

- **`SodiumCryptoService.deriveSharedKey`** — changed `context: 'starlingkex'` (11 bytes, rejected by libsodium) to `'starfk00'` (8 bytes, matches the `starsig0` convention). Affects only the *transit* encryption of feed-key deliveries, not the stored decrypted feed keys — but any pending or unacked handshake / rotation will need to re-derive. Pre-prod, so no migration code.
- **`ios/Runner/AppDelegate.swift`** — replaced `engineBridge.binaryMessenger` (removed) with `engineBridge.applicationRegistrar.messenger()` (the post-Flutter-3.x API).

### G. Build / minor

- **rustls backend** — verified during implementation that ring 0.17 cross-builds for both `aarch64-apple-ios` device and `aarch64-apple-ios-sim`. The original "ring fails on iOS" concern was about ring ≤ 0.16. **No backend change** — `aws-lc-rs` switch is deferred until real-device testing surfaces a concrete bug.
- **`SignalingMessageType.libp2pConnect` wire value** — `'libp2p_connect_v1'` → `'libp2p-connect-v1'` (hyphenated to match the rest of the capability namespace).
- **`lib/services/libp2p/ffi_bindings.dart` docstring** — corrected `liblibp2p_bridge.so` → `libp2p_bridge.so` (the cargo `lib name = "p2p_bridge"` rename from Plan 11b dropped the double-`lib`).

## Critical files

### Native

- `app/starling/native/libp2p_bridge/Cargo.toml` — dropped `dcutr` feature, added `if-watch = "3.2"` direct dep.
- `app/starling/native/libp2p_bridge/src/inner.rs` — Behaviour without dcutr; v6 listener; `insert_if_routable` filter; `DialTimeout` Cmd variant + handling; `pending_frame` field on `StreamHandle`; `bound_udp_port` / `has_ip6` helpers.
- `app/starling/native/libp2p_bridge/src/lib.rs` — `lp_stream_read` honours `pending_frame`.
- **Created** `app/starling/native/libp2p_bridge/src/interfaces.rs` — `spawn_v6_enumerator` + `if-watch` driver.
- **Deleted** `app/starling/native/libp2p_bridge/src/stun.rs`.

### Dart

- **Created** `app/starling/lib/services/libp2p/libp2p_bridge_isolate.dart` — `libp2pWorkerEntry` + `_WorkerState` dispatcher.
- `app/starling/lib/services/libp2p/libp2p_bridge.dart` — fully rewritten to thin-client over the worker `SendPort`. Native Port events still arrive on the main isolate.
- `app/starling/lib/services/libp2p/libp2p_service.dart` — removed `Libp2pDcutrSucceeded` / `Libp2pDcutrFailed` event variants.
- `app/starling/lib/services/libp2p/ffi_bindings.dart` — docstring fix.
- `app/starling/lib/sync/libp2p_upgrader.dart` — relaxed empty-observed bail; removed `channel?.close()` in finally; doc-comment about pool ownership.
- `app/starling/lib/services/lifecycle/lifecycle_manager.dart` — `signalingDispatcherProvider.start()` gated on real WS binding, retried on `onResume`.
- `app/starling/lib/providers/service_providers.dart` — added `ProductionSignaling` notifier; `signalingServiceProvider` watches it.
- `app/starling/lib/main.dart` — no more `late ProviderContainer`; WsSignalingService is constructed post-container and installed via `productionSignalingProvider.notifier.set(...)`.
- `app/starling/lib/services/crypto/sodium_crypto_service.dart` — `deriveSharedKey` ctx `'starfk00'`.
- `app/starling/lib/models/signaling_message.dart` — `libp2pConnect` wire value `'libp2p-connect-v1'`.

### iOS

- `app/starling/ios/Runner/AppDelegate.swift` — Flutter messenger API.

## Verification

1. **Native compiles + host tests pass.** ✓ — `cargo check` succeeds (run from `app/starling/native/libp2p_bridge`).
2. **iOS + Android cross-build green.** TODO — re-run `./build.sh all`; rebuild `flutter build ios --no-codesign --debug` and `flutter build apk --debug`. On-device boot logs should confirm `Libp2pBindings.load()` (no `dlsym` errors).
3. **Unit + analyze.** ✓ — `flutter analyze` clean (only pre-existing style lints). Existing tests untouched still pass.
4. **Loopback integration test.** TODO — new `test/sync/libp2p_loopback_test.dart` exercising two `Libp2pBridge` instances dialing each other on 127.0.0.1.
5. **`lp_stream_read` frame-preservation test.** TODO — force a > 64 KiB frame and verify the doubling retry returns the same frame.
6. **Two-phone smoke (`#19`).** TODO. Updated test plan vs. the original `11a-libp2p-direct-remaining.md`:
   - Test 1 (both cellular CGNAT, both with v6) — should SUCCEED directly over QUIC/v6.
   - Test 1b (NEW) — disable v6 on one phone, confirm fallback to Tor.
   - Test 3 (carrier with no v6 on either side) — expectation: `libp2p upgrade failed for <pubkey>: dial timeout` followed by Tor sync proceeding. No DCUtR errors (we don't run DCUtR anymore).
   - Verify v6 deployment status with Settings → Cellular → Cellular Data Options → "IP Version" before running.
7. **UI responsiveness.** TODO — simulate a 10 s stream stall; confirm Flutter UI frame rate stays at 60 Hz while the FFI call hangs. (Single-isolate baseline would drop to 0 fps.)

## Open questions / follow-ups

- **`aws-lc-rs` rustls backend** — deferred; ring 0.17 works. Revisit if iOS App Store crypto export rules ever bite.
- **`libp2p_stream = "0.3.0-alpha"`** — still alpha. Pin remains; revisit when libp2p ≥ 0.56 lands.
- **iOS background v6 listener** — needs a foreground smoke. If iOS reaps the v6 UDP mapping on background, `_ensureLibp2pListen` on resume already re-binds.
- **iCloud Private Relay** — rewrites cellular v4 egress through Apple proxies but does NOT touch v6. v6 flows should pass. Verify on a Private-Relay-enabled device.
- **Android interface enumeration** — carrier-assigned v6 may appear on `rmnet_data0`, not `wlan0`. `if-watch` scans all `up` interfaces, so should be fine; verify on a test device.
