# Starling

A private, peer-to-peer social feed. No servers, no ads, no algorithm. End-to-end encrypted, runs on your phone.

**Home:** [starlinghome.app](https://starlinghome.app) *(site coming soon)*
**Contact:** `hello@starlinghome.app` · **Security:** `security@starlinghome.app` · **Support:** `support@starlinghome.app`

Starling is a social feed for your real friends. You post photos and captions; the people you've added see them in chronological order. There is no explore page, no suggested users, no infinite scroll, and no company between you and your friends. Your posts live on your phone, encrypted, and sync directly to your friends' phones over LAN or Tor.

See [`pitch.md`](pitch.md) for the product positioning.

## Status

Pre-1.0. Phase 1 (the shipping target) is being built out across the numbered plans in [`app/plans/`](app/plans/). The Flutter app under [`app/starling/`](app/starling/) is the only thing currently in active development — the standalone Rust relay ([`relay/`](relay/)) is Phase 2.

## How it works

- **Identity**: Ed25519 keypair generated on first launch, backed up by a recovery phrase. No accounts, no usernames, no central registry.
- **Encryption**: Posts and media are encrypted with a per-author feed key (XChaCha20-Poly1305). Per-message keys are derived MegOLM-style from a chain root — `BLAKE2b-256(chainRoot || "starling-msg-key-v1" || u64_be(msg_seq))` — so forward-secrecy upgrades require only changing the derivation, not the wire format. Feed keys are shared with followers via X25519 Diffie-Hellman.
- **Networking**: Each device runs a small HTTP server (Dart `shelf`). Peers discover each other via mDNS on LAN, and via Tor onion services (embedded Arti, Rust FFI) on WAN.
- **Storage**: Drift over SQLite Multiple Ciphers (SQLCipher v4 mode), with the key in the OS keychain.
- **Sync**: Async. On app open, the client builds a want-list, exchanges manifests with reachable peers, and pulls missing events. Media is lazy-loaded.

For the system-level overview, see [`plans/starling-architecture.md`](plans/starling-architecture.md). The wire format lives in [`protocol/plans/protocol-spec.md`](protocol/plans/protocol-spec.md).

## Repository layout

```
app/
  app-spec.md           Architecture and responsibilities for the mobile app
  plans/                Sequential implementation plans (01–16)
  starling/             The Flutter app itself (Dart + native FFI)
    lib/                Dart sources (services, screens, providers, …)
    native/arti_bridge/ Rust crate wrapping Arti for Tor FFI
plans/
  starling-architecture.md   System-level architecture
protocol/plans/
  protocol-spec.md      Wire format, event model, envelope
relay/plans/
  relay-spec.md         Standalone relay (Phase 2)
pitch.md                Product pitch and positioning
UBIQUITOUS_LANGUAGE.md  Shared domain vocabulary
CLAUDE.md               Project notes for the Claude Code agent
```

## Building the app

Prerequisites:

- Flutter SDK (`^3.12.0-0`, matching `app/starling/pubspec.yaml`)
- Xcode (iOS 26+ deployment target) and/or Android SDK with NDK r28.2 (the `arti_bridge` Rust crate is built with NDK r28.2 for 16 KB page-size alignment)
- Rust toolchain (for the `arti_bridge` native library)

```bash
cd app/starling
flutter pub get
flutter run
```

The `sqlite3` native asset hook in `pubspec.yaml` selects the `sqlite3mc` (SQLite Multiple Ciphers) build automatically.

## Design principles

1. **No developer-operated infrastructure.** No relays, no push proxies, no signaling servers run by the project.
2. **Free forever.** No monetization, no paid tiers, no managed hosting. Public good, not a business.
3. **The crypto is invisible.** Users never see a key or a signature — they see friends and posts.
4. **Async by design.** Posts arrive when friends are around. The slower pace is the product.
5. **Self-hosting is a gradient.** Phone-to-phone by default; old phone as a relay is one toggle; standalone Rust relay (Phase 2) for self-hosters. Each level adds availability, not features.

## Tech stack

- **App**: Flutter (Dart), Riverpod for state, `go_router` for navigation
- **Crypto**: libsodium via the `sodium` Dart package
- **Storage**: `drift` over `sqlite3mc`
- **HTTP server**: `shelf` + `shelf_router`
- **Tor**: Arti (Rust) via a bespoke FFI bridge in `app/starling/native/arti_bridge/`
- **mDNS**: Bespoke platform channel (NWBrowser/NWListener on iOS, NsdManager on Android)
- **QR**: Bespoke AVFoundation/CameraX scanner, `qr_flutter` for rendering
- **Serialization**: CBOR
