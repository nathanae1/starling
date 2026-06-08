# Plan 11a — Remaining Work

> **Most of this doc has been completed by [Plan 11c](11c-libp2p-direct-fixes.md).**
> The remaining work below was either implemented (#10 Rust Swarm,
> #11 cross-build, #16 shelf-handler refactor for libp2p reuse,
> #17a inbound dispatch, #19 manual smoke prep) during Plan 11a/11b,
> or replaced by Plan 11c. Specifically, Plan 11c:
> - Dropped `dcutr` (the original §"NAT integration" plan can't work
>   without a relay; we now coordinate simultaneous-open ourselves and
>   accept the smaller traversal envelope).
> - Deleted the STUN module (reflexive ports can't match the QUIC
>   listener's port).
> - Added an IPv6 listener and per-interface v6 enumeration via
>   `if-watch` — the actual NAT-traversal mechanism on cellular.
> - Replaced the per-call FFI pattern with a dedicated worker isolate.
> - Fixed the `lp_stream_read` frame-loss bug, the
>   shared-channel-close bug, and the dial-timeout no-op.
>
> Test plan #19 (two-phone smoke) is still outstanding — see Plan 11c
> §Verification for the updated expectations.

Handoff doc. The Dart side of Plan 11a is complete and analyze-clean. The
native crate compiles (`cargo check` passes against the libp2p 0.55 dep
tree) but every FFI body still returns `LP_ERR_UNIMPLEMENTED`. The full
feature stays dark behind `kLibp2pEnabled = false` until the native crate
ships.

This doc lists what's left, in roughly the order someone should tackle it.
Open it next to `11a-libp2p-direct.md` for the design context.

## Status snapshot

**Done (commits should be reviewable as a stack):**
- `PeerTransport.libp2pDirect` enum, `kLibp2pEnabled` feature flag,
  `ConnectionCard` capability `libp2p-direct-v1`.
- `PeerReachabilityMonitor` priority `[lan, libp2pDirect, relay, tor]`
  with libp2pDirect excluded from the periodic probe loop (it's
  upgrader-promoted, not monitor-probed) and a new public
  `markReachable(pubkey, transport, baseUrl)`.
- `TransportRouter` switch dispatch with nullable `libp2p` slot.
- Abstract `Libp2pService`, stub `Libp2pBridgeStub`, FFI bindings
  declared in `lib/services/libp2p/ffi_bindings.dart`.
- `Libp2pNetworkService` (NetworkService + SyncTransport over libp2p
  streams, byte-identical CBOR to LAN/Tor) with 5 passing unit tests.
- `Libp2pUpgrader` (initiator + responder DCUtR coordination over the
  existing `SignalingService`, per-peer backoff, post-dial
  `/starling/sync/ping/1` health gate).
- `SignalingMessageType.libp2pConnect` added.
- `SyncEngine._syncOnePeer` fire-and-forget hook gated on
  `kLibp2pEnabled && transport == tor`.
- Riverpod providers wired (`libp2pServiceProvider`,
  `libp2pNetworkServiceProvider`, `libp2pUpgraderProvider`,
  `syncTransportProvider` / `syncEngineProvider` updated).
- `LifecycleManager.onResume` calls `libp2p.init + listen`;
  `onPause` calls `libp2p.shutdown` (gated by foreground-service-on-Android
  same as Tor).
- Native `libp2p_bridge/` skeleton (Cargo.toml + libp2p 0.55 with
  QUIC/Noise/yamux/DCUtR/Identify/Ping, 16KB-page-size `.cargo/config`,
  `build.sh` for iOS xcframework + Android cargo-ndk, cbindgen,
  `lib.rs` + `inner.rs` stubs). `cargo check` on host passes against
  the dep tree.

**Not done — what this doc covers:**

| # | Task                                  | Blocking? | Where           |
|---|---------------------------------------|-----------|-----------------|
| 10 | Rust Swarm + event loop + STUN       | Yes       | `native/libp2p_bridge/src/` |
| 11 | iOS xcframework + Android .so builds | Yes       | `build.sh`, Xcode, Gradle |
| 16 | Shelf handler refactor for libp2p reuse | No     | `lib/server/handlers/` |
| 17a | Wire `handleInboundLibp2pConnect`   | Yes for responder side | DI in `service_providers.dart` |
| 18b | Loopback integration test            | No        | `test/sync/` |
| 19 | Two-phone manual smoke + flag flip   | Yes       | physical devices |

Only #10, #11, #17a, and #19 are on the critical path to "libp2p works
end-to-end." #16 makes the inbound libp2p stream side reuse existing HTTP
business logic — necessary for responder peers to actually answer sync
calls over libp2p, but doesn't block initiator-side upgrade attempts.

---

## #10 Rust Swarm + event loop + STUN

**File:** `native/libp2p_bridge/src/lib.rs` (replace stub bodies) and
`src/inner.rs` (real state).

**Acceptance:** `cargo build --release` succeeds; the host binary boots,
binds a QUIC listener, derives a stable PeerId from an Ed25519 seed,
accepts a `lp_dial_direct` to itself on `127.0.0.1`, opens a stream on a
test protocol, round-trips a length-delimited frame.

### What to build

```rust
// src/inner.rs — replace placeholder
pub struct Inner {
    pub swarm: tokio::sync::Mutex<Swarm<Behaviour>>,
    pub local_peer_id: PeerId,
    pub native_port: AtomicI64,                // 0 until lp_set_event_port
    pub conns: RwLock<HashMap<i64, ConnectionId>>,   // FFI conn_id -> libp2p
    pub conn_counter: AtomicI64,
    pub streams: RwLock<HashMap<i64, StreamState>>,  // FFI stream_id -> chan
    pub stream_counter: AtomicI64,
    pub inbound_handlers: RwLock<HashSet<String>>,   // registered protocols
    pub observed_addrs: RwLock<HashSet<Multiaddr>>,
}

#[derive(NetworkBehaviour)]
struct Behaviour {
    identify: identify::Behaviour,
    dcutr: dcutr::Behaviour,
    ping: ping::Behaviour,
    // Custom protocol-stream behaviour for /starling/sync/*/1 protocols.
    // libp2p-stream (the unstable Stream behaviour) is the right primitive
    // here — it exposes a generic stream API per protocol.
    stream: libp2p_stream::Behaviour,
}
```

Pull `libp2p_stream` in via the `stream` feature of libp2p (not currently
in Cargo.toml — add it). It exposes `Control::accept(protocol)` for
inbound handlers and `Control::open_stream(peer, protocol)` for outbound.

### Event loop

```rust
tokio::spawn(async move {
    loop {
        tokio::select! {
            event = swarm.select_next_some() => handle_swarm_event(event),
            cmd = cmd_rx.recv() => handle_dart_command(cmd),
        }
    }
});
```

Commands come from FFI calls (dial, open_stream, write, etc.) over a
`tokio::sync::mpsc` channel. Each FFI call enqueues a command + a oneshot
reply channel; the FFI thread blocks on `recv()` from the oneshot to get
the result. This keeps the Swarm single-threaded (which it must be —
`Swarm` is `!Sync`).

### Dart Native Port delivery

Add `allo-isolate = "0.1"` (or wire `dart_api_dl.h` directly). On
`lp_init`, call `Dart_InitializeApiDL(init_api_dl_data)`. On
`lp_set_event_port(handle, port)`, store the port; on every interesting
Swarm event, CBOR-encode an event message and call
`Dart_PostCObject_DL(port, …)`.

Event shapes (CBOR maps; tag with `type` field):
- `peer_connected` `{ peer_id }`
- `peer_disconnected` `{ peer_id }`
- `identify_received` `{ peer_id, observed_addr, listen_addrs }`
- `dcutr_succeeded` `{ peer_id }`
- `dcutr_failed` `{ peer_id, reason }`
- `observed_addr_changed` `{ multiaddr }`
- `inbound_stream` `{ peer_id, protocol, stream_id }`

These map 1:1 to the `Libp2pEvent` sealed class on the Dart side
(`lib/services/libp2p/libp2p_service.dart`). When adding events, update
both sides together — there's no codegen.

### Streams

`libp2p_stream` returns a duplex stream per accept/open. The FFI surface
treats each stream as length-delimited: `lp_stream_write` does a single
`write_u32(len) + write_all(data)`, `lp_stream_read` does the inverse,
returning one frame per call. Use a `Cursor<Vec<u8>>` buffer per stream
so partial reads (the underlying `AsyncRead` may yield mid-frame) don't
lose data.

### Identity injection (security-sensitive)

```rust
// lp_init
let seed = std::slice::from_raw_parts(seed_ptr, 32).to_vec();
let mut seed_copy = seed.clone();  // local working buffer
let keypair = identity::Keypair::ed25519_from_bytes(&mut seed_copy)
    .map_err(...)?;
seed_copy.zeroize();  // explicit zeroize; the original `seed` Vec also
                      // drops at end of scope. Both must be zeroized
                      // before the function returns.
```

The Dart side already zeroizes its `Pointer<Uint8>` after `lp_init`
returns (or it should — verify in `Libp2pBridge` once it replaces the
stub).

### STUN client

Hand-rolled. STUN Binding Request is 20 bytes (transaction id + magic
cookie + length 0). Response carries `XOR-MAPPED-ADDRESS`. Default
servers: `stun.l.google.com:19302`, `stun.cloudflare.com:3478`,
`stun.services.mozilla.com:3478`. Run on every network-change event and
at app launch. Feed results into `observed_addrs` via the same path as
libp2p Identify "observed_addr" reports.

Pre-existing reference: the Tor architecture doc
`plans/starling-architecture.md:100` already commits to STUN as
acceptable infrastructure. No new privacy regression.

### Gotchas

- **rust-libp2p QUIC on iOS**: rust-libp2p QUIC uses `quinn` which uses
  `rustls`. On iOS, the rustls dep chain has historically had issues with
  `ring` (the crypto backend) due to assembly support. Verify a real
  iOS-arm64 cross-compile early; you may need to swap `ring` for
  `aws-lc-rs` via feature flags. Same risk on Android-arm64 (less likely
  but check).

- **PeerId derivation**: the Dart side does NOT derive a remote peer's
  PeerId from their Ed25519 pubkey. It learns the PeerId from the
  `libp2p-connect-v1` signaling message payload (`peer_id` field).
  Keep that. Implementing the multihash + protobuf encoding in Dart
  would be a substantial rabbit hole — and is unnecessary because the
  upgrader exchanges peer ids as the first step of every coordination.

- **Catch_unwind**: every `extern "C"` function MUST wrap its body in
  `catch_unwind(AssertUnwindSafe(|| { … }))`. The skeleton's
  `guard_handle` / `guard_handle_i64` helpers already do this; reuse them.

- **Tokio runtime**: build a multi-thread runtime owned by the handle.
  Drop it during `lp_shutdown` to release listening sockets and abort
  background tasks.

---

## #11 Cross-compile for iOS xcframework + Android .so

**Files:** `build.sh` (host script — already wired), Xcode project,
`android/app/build.gradle`.

**Acceptance:** `./build.sh all` writes
`ios/Runner/libp2p_bridge.xcframework` and
`android/app/src/main/jniLibs/{arm64-v8a,x86_64}/liblibp2p_bridge.so`;
the app builds and launches on both platforms; `DynamicLibrary.process()`
on iOS and `DynamicLibrary.open('liblibp2p_bridge.so')` on Android
resolve `lp_init` without `ProcessException: dlsym`.

### Prerequisites

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk
export ANDROID_NDK_HOME=…  # NDK r28.2 or later (16KB alignment)
```

### iOS

The `.cargo/config.toml` is already set up for the 16KB page-size flags
on Android. iOS doesn't need the equivalent. `build.sh` runs
`xcodebuild -create-xcframework` combining device + simulator slices.

In Xcode, drag `ios/Runner/libp2p_bridge.xcframework` into the Runner
target's "Frameworks, Libraries, and Embedded Content" — set to "Do Not
Embed" (it's a static library). This mirrors how `arti_bridge.xcframework`
is wired today; check the existing entry in `Runner.xcodeproj` for the
exact build setting.

### Android

`cargo-ndk` writes `.so` files into `jniLibs/`. Verify the Gradle build
picks them up automatically (it should — Gradle ships an
`androidResources.assets.srcDirs += jniLibs` default for module
android.applicationVariants). If a fresh `flutter build apk` doesn't
include the .so, check `android/app/build.gradle` for any explicit
`packagingOptions` excludes.

### Validation

After the .so / .xcframework is in place, run the app on a device. The
stub bridge's `lp_init` is a no-op in Dart but the FFI lookup still
happens at first call. If it succeeds without throwing, dispatch tables
are wired. The real bridge will then activate the moment `lp_init`
returns a non-null handle (which it now will).

---

## #16 Shelf handler refactor for libp2p reuse

**Files:** every file under `lib/server/handlers/` plus their tests.

**Why:** When the Rust bridge delivers an inbound libp2p stream (via the
`inbound_stream` event), the Dart side needs to feed it to handler logic
that produces the same CBOR response the HTTP shelf handlers would. The
cleanest pattern is to extract that logic into pure functions both call
sites share.

**Refactor pattern (per handler):**

```dart
// lib/server/handlers/manifest_handler.dart — current shelf-only shape:
Handler manifestHandler({ required Deps … }) {
  return (Request request) async {
    final since = int.tryParse(request.url.queryParameters['since'] ?? '');
    …
    final manifest = await … build manifest …;
    return Response.ok(manifest.toBytes(), …);
  };
}

// after refactor:
Future<Uint8List> handleManifestRequest(
  ManifestRequest req,
  Deps deps,
) async {
  // pure CBOR-in / CBOR-out
}

Handler manifestHandler({ required Deps deps }) {
  return (Request request) async {
    final req = ManifestRequest.fromHttp(request);
    final bytes = await handleManifestRequest(req, deps);
    return Response.ok(bytes, …);
  };
}
```

Then on the libp2p side, the `Libp2pBridge` calls `libp2p.registerInboundHandler(protocol, (stream) { … })` and the handler decodes the stream's first CBOR frame into the same `ManifestRequest`, calls `handleManifestRequest`, writes the response, closes.

Apply to all 7 protocol routes:
- `/starling/sync/manifest/1`
- `/starling/sync/events/1`
- `/starling/sync/events-push/1`
- `/starling/sync/media/1`
- `/starling/sync/follow-request/1`
- `/starling/sync/follow-accept/1`
- `/starling/sync/ping/1` — trivial, accepts empty map, returns empty map.

Existing handler tests assert on HTTP-level shapes; after the refactor
they should mostly continue to work (`fromHttp` parsing is still tested).
Add new tests for `handleManifestRequest` against in-memory `Deps` to
cover the pure function directly.

---

## #17a Wire inbound libp2p-connect dispatch

**File:** likely `lib/providers/service_providers.dart` or a new tiny
dispatcher module.

**Why:** `Libp2pUpgrader.handleInboundLibp2pConnect(channel, message)`
is the responder side of the DCUtR coordination. It is not currently
called by anything. The shelf signaling handler authenticates inbound
WebSocket upgrades and invokes a single `onInboundConnection` callback
on the `SignalingService`. Plan 16 (voice rooms) also wants that
callback. They need to share.

**Suggested design:**

```dart
class SignalingDispatcher {
  SignalingDispatcher(this._signaling, this._upgrader, /* voice rooms */);

  void start() {
    _signaling.onInboundConnection((channel) {
      channel.messages.listen((bytes) {
        final msg = SignalingMessage.fromBytes(bytes);
        switch (msg.type) {
          case SignalingMessageType.libp2pConnect:
            _upgrader.handleInboundLibp2pConnect(channel, msg);
          case SignalingMessageType.roomInvite:
          case SignalingMessageType.offer:
          case … :
            // voice-room dispatch (Plan 16)
        }
      });
    });
  }
}
```

Wire `SignalingDispatcher.start()` from `LifecycleManager.start()`
behind `kLibp2pEnabled || kVoiceChatroomsEnabled`. The dispatcher
becomes the single owner of `signaling.onInboundConnection`.

---

## #18b Loopback integration test

**File:** new `test/sync/libp2p_loopback_test.dart`.

**Acceptance:** Two `Libp2pBridge` instances in one Dart test process,
each bound to `127.0.0.1`, dial each other, exchange a full sync run
(manifest + events + media) via real libp2p streams. Validates the
CBOR-on-stream framing and protocol multiplexing end-to-end without
exercising DCUtR/NAT (which is what #19 manual smoke is for).

Pseudocode:
```dart
final aliceBridge = Libp2pBridge();
await aliceBridge.init(tempDir, aliceSeed);
await aliceBridge.listen();
final bobBridge = Libp2pBridge();
await bobBridge.init(tempDir2, bobSeed);
await bobBridge.listen();

// Cross-dial via the local listen addrs (bypassing DCUtR signaling).
await aliceBridge.dialDirect(bobBridge.localPeerId, await bobBridge.observedAddrs());

// Now run a manifest fetch from alice's NetworkService to bob.
final svc = Libp2pNetworkService(libp2p: aliceBridge);
final manifest = await svc.fetchManifest(/* PeerConnection wrapping bob */);
expect(manifest.events, …);
```

Add a tiny "loopback dial" helper to `Libp2pService` if it makes the
test cleaner — `dialDirect` already accepts arbitrary multiaddrs.

This test depends on #10 (real Rust bridge) being done. Until then it
either skips or is gated `@TestOn('vm') @SkippedTag('libp2p-bridge')`.

---

## #19 Manual smoke test + flag flip

**Pre-reqs:** #10 and #11 done. App installed on two physical phones,
each with a follow of the other established.

**Test plan (sequential, all must pass):**

1. **Both phones cellular, both behind carrier-grade NAT.**
   - Trigger a sync from phone A.
   - In `developer.log` filter on `libp2p_upgrader`, expect:
     - `libp2p upgrade start pubkey=...`
     - `libp2p upgrade ok pubkey=... peer_id=...`
   - Confirm next sync from A goes over libp2p (PeerConnection.baseUrl
     starts with `libp2p://` rather than `http://*.onion`).
   - Confirm latency drops from ~2-5s/req over Tor to <500ms over QUIC.

2. **One phone moved to home WiFi behind a residential NAT.**
   - Re-trigger sync.
   - Expect upgrade to succeed (residential NAT is usually full-cone or
     restricted-cone — DCUtR handles both).

3. **One phone moved to cellular with carrier-grade symmetric NAT
   (T-Mobile USA is a known case).**
   - Re-trigger sync.
   - Expect upgrade to FAIL gracefully; sync continues over Tor.
   - In logs, expect `libp2p upgrade failed` with reason ~ "timeout" /
     "no path found." No app-level errors.

4. **Cellular drop mid-sync.**
   - Start a sync, then airplane mode the receiving phone.
   - Sender's libp2p connection should fail; `markUnreachable` runs;
     next pump (~60s) re-routes over Tor.

5. **Long-run battery check.**
   - Leave the app in foreground for 30 minutes with libp2p active.
   - Check Battery usage (iOS Settings → Battery, Android Settings →
     Battery → App usage). Expect ≤10% additional drain vs. Tor-only
     baseline. If higher, investigate QUIC keepalive frequency and
     Identify ping interval.

**Flag flip:** edit `lib/utils/feature_flags.dart`,
`kLibp2pEnabled = true`, commit. Land the commit only after all five
smoke tests pass.

---

## Open questions / decisions you'll hit

These aren't blockers but they'll come up during #10:

- **STUN crate vs. hand-rolled.** The Cargo.toml currently does NOT
  depend on a STUN crate. Hand-rolling ~50 lines of binding request
  parsing avoids a dep; the `stun_codec` crate is the alternative.
  Pick one early.

- **QUIC keepalive frequency.** rust-libp2p QUIC defaults are tuned for
  desktop. On cellular, NAT mappings can evict idle UDP flows after
  30-60s. May need to drop the keepalive interval; benchmark in test 5.

- **Connection idle eviction.** The plan calls for the bridge to drop
  libp2p connections after 5 min idle. libp2p `connection-limits` or a
  manual timer in the event loop both work. Pick before #18b so the
  test asserts the right behavior.

- **`libp2p_stream` is unstable.** It's the right primitive but the API
  has been moving across recent libp2p versions. Pin to a known-good
  release (0.55 is current as of this doc); if you need to bump rustsec
  later, re-validate the stream API.

- **Background sync coexistence.** Plan 14 background sync explicitly
  doesn't use libp2p. Verify the background runner
  (`lib/services/background/background_sync_runner.dart`) doesn't pull
  `libp2pNetworkServiceProvider` directly — it should construct its own
  `TransportRouter(lan: …, tor: …)` without a libp2p slot. Confirmed in
  the current code (line 158: `TransportRouter(lan: lan, tor: torLan)`).

---

## Risk register

- **rustls/ring on mobile.** QUIC on iOS/Android via rustls may need
  `aws-lc-rs` instead of `ring`. Validate first thing in #11.
- **iOS App Store review.** First-party Tor + STUN + libp2p stack is
  unusual. Have a clear "this is a P2P social app; UDP is for direct
  peer connections" reviewer note ready.
- **Apple background networking.** iOS aggressively reaps UDP sockets
  in background. The lifecycle wiring already shuts libp2p down on
  `paused`; double-check no other path keeps the socket open.
- **libp2p spec evolution.** DCUtR has been stable for years now; QUIC
  protocol id versioning has not. If you bump rust-libp2p later, run a
  cross-version interop test (old client → new client and vice versa)
  before shipping.

---

## Files of interest

| Concern | Path |
|---|---|
| Plan | `app/plans/11a-libp2p-direct.md` |
| Feature flag | `app/starling/lib/utils/feature_flags.dart` |
| Abstract service | `app/starling/lib/services/libp2p/libp2p_service.dart` |
| Stub bridge | `app/starling/lib/services/libp2p/libp2p_bridge.dart` (rename to `_stub.dart` when adding the real bridge alongside) |
| FFI bindings | `app/starling/lib/services/libp2p/ffi_bindings.dart` |
| NetworkService | `app/starling/lib/services/libp2p_network_service.dart` |
| Upgrader | `app/starling/lib/sync/libp2p_upgrader.dart` |
| Reachability monitor | `app/starling/lib/sync/peer_reachability_monitor.dart` |
| Transport router | `app/starling/lib/sync/transport_router.dart` |
| Sync engine hook | `app/starling/lib/sync/sync_engine.dart` |
| DI | `app/starling/lib/providers/service_providers.dart`, `sync_provider.dart` |
| Lifecycle | `app/starling/lib/services/lifecycle/lifecycle_manager.dart` |
| Native crate | `app/starling/native/libp2p_bridge/` |
| Tests | `app/starling/test/services/libp2p_network_service_test.dart` |
