# Plan 11a — libp2p Direct-Connect Transport Tier

> **Superseded in part by [Plan 11c](11c-libp2p-direct-fixes.md).**
> The architecture below shipped end-to-end but a post-implementation
> review found the §"DCUtR signaling" + STUN reflexive-address path
> cannot work without a libp2p relay (which we explicitly do not have).
> Plan 11c dropped `dcutr::Behaviour` and the STUN module, added an
> IPv6 listener + per-interface v6 enumeration, and moved the Dart FFI
> bridge into a dedicated long-lived worker isolate (replacing the
> per-call `Isolate.run` pattern this doc inherited from arti). Read
> 11c first if you want the *current* shape of the tier; sections
> below describe the original design and remain accurate where Plan
> 11c didn't touch them (Connection card, Application protocol over
> libp2p, Sync flow integration, Lifecycle).

## Context

Starling's networking today is a two-tier ladder per peer: LAN (mDNS + HTTP) when on the same network, else Tor (Arti onion services + HTTP). LAN is rare in practice — most followers aren't on your WiFi. So the common path is **Tor**, with multi-second latency that makes sync feel sluggish and limits how chatty the app can be (no WebSocket-grade interactivity over Tor circuits in practice).

`protocol-spec.md:304-317` and `plans/starling-architecture.md:91-103` already specify a "Tier 2" optimization: Tor handles signaling, peers attempt simultaneous-open NAT hole-punching, fall back to Tor on failure. Building this from scratch means implementing STUN, NAT-type detection, port prediction, timing coordination, and TCP/UDP fallback. libp2p's DCUtR + QUIC has solved this with measured ~70-80% success rates across mobile NATs.

**Goal**: ship the Tier 2 fast path using rust-libp2p (DCUtR + QUIC + Noise + yamux + Identify) via FFI, as a sibling of `arti_bridge`. Preserve all other architecture. The relay (Plan 15) is just another peer at the transport layer — same {LAN, libp2p-direct, Tor} ladder applies. Plan 15 is paused; it resumes after this lands and inherits the new transport for free.

**Non-goals**: replacing mDNS, replacing the Plan 15 store-and-forward relay, libp2p Kademlia/DHT/GossipSub/Circuit-Relay, transport encryption changes (libsodium content encryption stays canonical; Noise is defense-in-depth on the wire).

## Plan number & ordering

Slot as **Plan 11a** (extends Plan 11 Tor WAN). Plan 15 stays paused; resume after 11a ships. Plan 14 (background sync) is unaffected — background sync remains Tor-only (no foreground UDP listener, no battery cost).

## Architecture

### Transport stack on the Dart side

```
PeerReachabilityMonitor._priority = [lan, libp2pDirect, tor]
```

`PeerConnection` (`lib/services/types.dart`) gets a new transport variant `libp2pDirect`. The `baseUrl` for a libp2p connection is a synthetic `libp2p://<peer-id>` string — the bridge resolves it back to a `PeerId` internally. No multiaddrs leak into `NetworkService`/`SyncTransport` interfaces.

`TransportRouter._pick` dispatches `libp2pDirect → _libp2p` (a `Libp2pNetworkService`).

### Library subset

rust-libp2p features: `quic`, `noise`, `yamux`, `dcutr`, `identify`, `tokio`, `ed25519`. No mDNS, no AutoNAT (we use STUN), no relay client/server, no Kad, no Gossip.

### Identity

libp2p PeerId is deterministically `multihash(Ed25519 pubkey)`. The bridge accepts the Ed25519 *seed* (32 bytes — extract via libsodium `crypto_sign_ed25519_sk_to_seed` on the Dart side) at `lp_init`, constructs `Keypair::ed25519_from_bytes`, zeroizes its copy after use. PeerId never needs to be stored in the connection card — receivers derive it from the card's `pubkey` field.

### DCUtR signaling: ride on existing `SignalingService`

`lib/services/signaling_service.dart` is a persistent WebSocket channel already designed for "SDP offers/answers, ICE candidates" (Plan 16). DCUtR coordination is the same shape. **Reuse it.** Don't add a new HTTP endpoint.

Add a new `SignalingMessage` variant for libp2p coordination:
```
{
  type: "libp2p-connect-v1",
  initiator_addrs: [<multiaddr bytes>, ...],
  nonce: <8 bytes>,
  punch_at_unix_ms: <int>,
}
```
Both peers send their candidate multiaddrs (STUN-discovered reflexive + local listen addrs), agree on a punch time ≥ now+800ms, and call `lp_dial_direct` in a synchronized window. DCUtR's standard protocol handles the rest.

Signaling channel is established lazily: when the sync engine decides to attempt an upgrade for a peer that doesn't already have one open, `SignalingService.connect(peer)` opens it (over LAN or Tor — whichever is currently reachable for that peer).

### Observed-address discovery: STUN

The bridge embeds a minimal STUN client. Queries Google/Cloudflare/Mozilla public STUN servers at app launch and on every network-change event (`Connectivity` plugin). Results populate `lp_observed_addrs` for inclusion in the signaling message. STUN servers are content-blind — they see only IP, never identity. This matches the architecture doc's existing privacy posture (`plans/starling-architecture.md:100`).

### Application protocol over libp2p

Define one libp2p protocol per existing HTTP route, length-delimited CBOR over a libp2p stream:

| Protocol ID | Equivalent HTTP |
|---|---|
| `/starling/sync/manifest/1` | `GET /manifest` |
| `/starling/sync/events/1` | `GET /events` |
| `/starling/sync/events-push/1` | `POST /events` |
| `/starling/sync/media/1` | `GET /media/{hash}` |
| `/starling/sync/follow-request/1` | `POST /follow-request` |
| `/starling/sync/follow-accept/1` | `POST /follow-accept` |
| `/starling/sync/ping/1` | reachability probe |

Per-call shape: open stream → write CBOR request (same fields the HTTP handler decodes from query+body, bundled into one map) → read CBOR response → close. Response payloads are **byte-identical** to the HTTP body (e.g., `Envelope.toBytes()`), so `ManifestExchange`, `Envelope.fromBytes`, all decryption code, the rest of `SyncEngine`, unchanged.

### Connection card

Add `libp2p-direct-v1` to `ConnectionCard.capabilities`. Do **not** add libp2p endpoint addresses to the card — addresses change with networks, the card is exchanged once at follow-time. Capability presence gates whether the sync engine attempts an upgrade; absence means stay on Tor permanently for that peer.

### Sync flow integration

In `SyncEngine._syncOnePeer`, after `PeerConnectionFactory.resolve` returns:

```
if connection.transport == PeerTransport.tor
   && follow.card has libp2p-direct-v1 capability
   && Libp2pService.isReady
   && no recent failed upgrade (60s backoff after failure):
       fire-and-forget Libp2pUpgrader.tryUpgrade(connection, follow)
       proceed with current Tor connection
```

`tryUpgrade` sends the `libp2p-connect-v1` signaling message, calls `lp_dial_direct` at the agreed time, on `ConnectionEstablished` + first successful `/starling/sync/ping/1` round-trip calls `PeerReachabilityMonitor.markReachable(pubkey, libp2pDirect, "libp2p://<peer-id>")`. Next `bestConnectionFor` returns libp2p. Reachability state is session-scoped only — NAT mappings expire, restart starts fresh.

Connection pooling: libp2p Swarm pools by `PeerId` internally. `Libp2pNetworkService` keeps `Map<PeerId, ConnId>`, opens fresh streams per call, lets the swarm idle-evict after 5 min.

### Lifecycle

- `Libp2pBridge` constructed at app launch (cheap — FFI handle only).
- `lp_listen` deferred to first foreground sync. UDP listener + QUIC keepalives chew battery.
- `AppLifecycleState.paused/inactive` → `lp_shutdown`. Reconstruct on `resumed`.
- Background sync (Plan 14) does not touch libp2p — Tor only.

### Failure modes

- DCUtR dial timeout: 8s end-to-end. On timeout, stay on Tor; mark `libp2pDirect` unreachable for that peer with the existing `_backoffSeconds = [10, 30, 60, 120]` ladder in `peer_reachability_monitor.dart`.
- Mid-sync libp2p drop (once upgraded): catch `Libp2pStreamException` in `_syncOnePeer`, `markUnreachable(pubkey, libp2pDirect, e)`. Next pump cycle (~60s) succeeds on Tor.
- Bridge panic: `catch_unwind` per FFI call (mirror arti pattern); 3 consecutive panics → reconstruct handle; further failure → disable libp2p transport for the session, sync continues LAN+Tor.

## Critical files

### Create

- `app/starling/native/libp2p_bridge/` — Rust FFI crate. Mirror `native/arti_bridge/` structure: `Cargo.toml`, `src/lib.rs`, `src/inner.rs`, `build.rs`, `build.sh`, `include/libp2p_bridge.h`. Reuse the 16KB-page-size rustflags in `.cargo/config.toml`.
- `app/starling/lib/services/libp2p/ffi_bindings.dart` — FFI bindings + `dart_api_dl` native-port init (events delivered via `Dart_PostCObject_DL` for ordered, lossless event stream — same reasoning as for richer event sources).
- `app/starling/lib/services/libp2p/libp2p_service.dart` — abstract `Libp2pService` (analogous to `TorService`): `init(seed)`, `listen()`, `observedAddrs()`, `addObservedAddr()`, `dialDirect(peerId, addrs, timeout)`, `openStream(conn, protocol)`, `registerInboundHandler(protocol, onStream)`, `events`, `shutdown()`.
- `app/starling/lib/services/libp2p/libp2p_bridge.dart` — concrete impl wrapping FFI in `Isolate.run` for blocking ops (mirror `ArtiTorService` pattern in `lib/services/tor/arti_tor_service.dart`).
- `app/starling/lib/services/libp2p_network_service.dart` — implements `NetworkService` + `SyncTransport` over libp2p streams.
- `app/starling/lib/sync/libp2p_upgrader.dart` — orchestrates the signaling-message exchange + scheduled dial + reachability monitor update.
- `app/plans/11a-libp2p-direct.md` — plan document checked into the repo.
- `app/starling/lib/utils/feature_flags.dart` — new file, single `const kLibp2pEnabled = false;` (flip after smoke tests pass).

### Modify

- `app/starling/lib/services/types.dart` — add `PeerTransport.libp2pDirect`.
- `app/starling/lib/sync/transport_router.dart` — add `_libp2p` field, extend `_pick` switch.
- `app/starling/lib/sync/peer_reachability_monitor.dart` — extend `_priority`, add libp2p probe via `/starling/sync/ping/1`, expose `markReachable(pubkey, transport, baseUrl)` for the upgrader to call.
- `app/starling/lib/sync/sync_engine.dart` — invoke `Libp2pUpgrader.tryUpgrade` fire-and-forget per §"Sync flow integration".
- `app/starling/lib/models/connection_card.dart` — append `libp2p-direct-v1` to the default capabilities list.
- `app/starling/lib/services/signaling_service.dart` / `ws_signaling_service.dart` — add `libp2p-connect-v1` message variant. (Confirm shape against existing `SignalingMessage` types before writing code.)

## Verification

1. **Unit**: `Libp2pNetworkService` against a fake `Libp2pService` recording (protocol, payload) pairs and returning canned CBOR. Reuse every existing `LanNetworkService` test fixture — wire-level CBOR contracts are identical.
2. **Loopback integration**: two `Libp2pBridge` instances in one Dart test process dialing each other on `127.0.0.1`. Run existing `sync_engine_test` scenarios with both peers on the loopback bridge. Doesn't exercise DCUtR but validates protocol multiplexing and CBOR framing end-to-end.
3. **NAT integration (CI-optional)**: two containers behind separate userspace NATs (symmetric vs. full-cone via `iptables MASQUERADE`) running the Dart binary. Verify direct connection establishes after `libp2p-connect-v1` exchange over a Tor-routed `SignalingChannel`.
4. **Manual smoke (gate flag flip)**: two phones on different cellular carriers. Capture confirms post-upgrade sync traffic flows over QUIC/UDP, not Tor. Then move one phone to WiFi behind home NAT — confirm upgrade still works. Then disable cellular on one phone mid-sync — confirm graceful fall-back to Tor within one pump cycle.
5. **Rollout**: ship behind `kLibp2pEnabled = false`. Flip to `true` after smoke (3). Older clients without `libp2p-direct-v1` in their card capability list never trigger an upgrade attempt — zero protocol breakage.

## Open questions deferred to implementation

- Exact STUN crate vs. hand-rolled binding request (~20 bytes — leaning hand-rolled to avoid dep).
- Whether to publish a single libp2p `keep-alive` ping protocol vs. relying on QUIC's own keepalive frames (likely the latter, but verify on cellular NATs which can be aggressive about idle-mapping eviction).
- Whether the `Libp2pNetworkService` should expose libp2p connection telemetry (RTT, current path) into the existing reachability monitor UI (Plan 11c) — probably yes, but a small UI-only follow-up.
