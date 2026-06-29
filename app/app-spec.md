# Mobile App

The Flutter app is the core of Starling. It's the client, the server, the key manager, and the identity — all in one. Every user interaction, crypto operation, and network connection happens here.

**Target audience**: People who want a private social space with their real friends — no algorithm, no ads, no strangers, no corporation reading their messages. They don't care about cryptography. They care about having a space that isn't designed to exploit them.

## Responsibilities

1. **Identity management** — keypair generation, recovery phrase backup
2. **Content creation** — capture/select photos, compose posts, sign and encrypt events
3. **On-device server** — serve your content to peers over LAN and Tor
4. **Sync** — pull content from followed accounts' endpoints (their device, their relay)
5. **UI** — feed, profiles, post creation, follow management, settings

## Architecture

```
+--------------------------------------------------+
|                    UI Layer                        |
|  Feed  |  Profile  |  Compose  |  Settings        |
+--------------------------------------------------+
|                  App Logic                         |
|  Sync Engine  |  Post Creation  |  Follow Mgr     |
+--------------------------------------------------+
|              Service Interfaces                    |
|  CryptoService  |  TorService  |  StorageService  |
+--------------------------------------------------+
|              FFI Implementations                   |
|  libsodium      |  Arti        |  SQLCipher       |
+--------------------------------------------------+
|               Platform Layer                       |
|  OS Keychain  |  Filesystem  |  Network            |
+--------------------------------------------------+
```

### Native Interop Boundary

All native library interop is isolated behind abstract Dart interfaces from day one. Each service has an abstract class defining the contract and an FFI implementation behind it:

- **`CryptoService`** — keypair generation, signing, verification, encryption, decryption, key exchange. Implemented via libsodium FFI.
- **`TorService`** — onion service lifecycle, circuit management, outbound connections via Tor. Implemented via Arti FFI.
- **`StorageService`** — encrypted database operations, queries, migrations. Implemented via SQLCipher FFI.

App logic and UI depend only on the abstract interfaces, never on FFI types or native pointers directly. This provides:
- **Testability**: mock implementations for unit tests without native libraries
- **Swappability**: if a native library needs to be replaced (e.g., Arti matures, a better SQLCipher binding appears), only the implementation changes
- **Platform channels as escape hatch**: if FFI proves unreliable for a specific service, the implementation can be swapped to a platform channel (Swift/Kotlin) without touching app logic

## Core Services

### Crypto Service

Abstract `CryptoService` interface. Default implementation wraps libsodium via FFI.

**Key management:**
- Generate Ed25519 identity keypair on first launch
- Derive recovery phrase (BIP-39 style, framed as "recovery phrase" in UI, never "seed phrase") for backup
- Store private key in OS keychain (iOS Keychain / Android Keystore)
- Convert Ed25519 to X25519 for Diffie-Hellman exchanges
- Generate feed key (XChaCha20-Poly1305 256-bit symmetric)

**Feed key rotation:**
- Triggered when a follower is removed
- Generate new feed key, distribute to all remaining followers
- Old feed key retained locally for decrypting historical content
- New posts use the new key
- Distribution happens lazily on next sync

**Event operations:**
- `sign(event) -> sig` — Ed25519 sign the event id
- `verify(event) -> bool` — verify signature against pubkey
- `encrypt(event, feed_key) -> EncryptedEvent` — sign first, then XChaCha20-Poly1305 encrypt with random nonce
- `decrypt(encrypted_event, feed_key) -> Event` — decrypt, then verify signature
- `encrypt_media(blob, feed_key) -> encrypted_blob` — encrypt with random nonce
- `decrypt_media(encrypted_blob, feed_key) -> blob`

**Nonces:** All nonces are random (24 bytes from a CSPRNG). Never derived from content. This avoids nonce reuse if the same content is posted twice.

**Key exchange:**
- `derive_shared_key(my_x25519, their_x25519) -> symmetric_key` — X25519 DH + libsodium `crypto_kdf` (BLAKE2b-based) with context `"starlingkex"` and info = `requester_pubkey || responder_pubkey || timestamp`
- `encrypt_feed_key(feed_key, shared_key) -> encrypted_feed_key`
- `decrypt_feed_key(encrypted_feed_key, shared_key) -> feed_key`

**Feed key storage at rest:**
Feed keys for followed accounts are stored encrypted in the database (encrypted by the SQLCipher database key). On app launch, feed keys are decrypted into an in-memory cache for the session. The cache is cleared when the app is terminated. This avoids per-event key derivation while keeping keys encrypted at rest.

### On-Device Server

A lightweight HTTP server running inside the app. Serves your own content to peers who request it.

- Built with Dart `shelf` package
- Endpoints:
  - `GET /manifest?since=T&until=T` — returns list of event IDs + timestamps this device has for its own pubkey
  - `GET /events?since=T` — returns encrypted events
  - `GET /media/{blake2b_hash}` — returns encrypted media blob
  - `GET /status` — health check, pubkey, protocol version
  - `POST /follow-request` — receive inbound follow requests
- Only serves content for the device owner's pubkey
- Listens on a random high port

**LAN exposure:**
- Registers via mDNS/Bonjour with service type `_starling._tcp`
- Other Starling apps on the same network discover it automatically
- Direct HTTP connection — content is already E2E encrypted
- Note: mDNS announcement reveals the device is running Starling, and HTTP metadata (request paths, timing) is visible to LAN observers. Accepted trade-off for LAN simplicity.

**Tor exposure:**
- Embeds Arti (Rust Tor client) via FFI
- Creates a Tor onion service pointing to the local HTTP server
- `.onion` address is persisted and included in the connection card
- Onion service runs when the app is in foreground
- On iOS: stops when backgrounded (OS constraint)
- On Android: can persist via foreground service (user opt-in)

### Networking Service

Manages outbound connections to peers.

**Connection resolution (per followed account):**
1. Check if target is on LAN (mDNS cache) — always tried first, fastest
2. Try relay endpoint (if listed in their connection card)
3. Fall back to Tor onion endpoint

**Sync engine:**

Sync runs on app open and on pull-to-refresh. It's the primary way content flows.

1. Build want list: for each followed pubkey, what events are we missing within the **sync window** (default 30 days)?
2. Discover reachable endpoints: mDNS scan + connection card endpoints for each followed account
3. For each reachable endpoint, exchange manifests: lightweight list of event IDs within the sync window
4. Pull events we're missing — prefer fastest source (LAN > relay > Tor)
5. Decrypt, verify signatures, store locally

**Sync window**: Only recent content syncs automatically. Older content exists on the author's device or relay but isn't fetched unless the user explicitly requests it. This keeps storage bounded and sync fast.

**Manifest exchange:**
```
Request:  GET /manifest?since=T&until=T
Response: { pubkey: "X", events: [{ id, created_at }], has_older: true }
```

The manifest is a lightweight list of event IDs. The requester compares against local DB and fetches only what's missing.

**Sync concurrency:**
- Max 5 parallel peer connections
- Process peers in order of expected speed (LAN first, then relay, then Tor)
- Deduplicate: if we already have an event, don't fetch it again

**Media fetching:**
- Fetch media lazily: download when the post scrolls into view, not during event sync
- Media fetched from the author's endpoint (device or relay)
- If the author is offline, show a placeholder and retry later

**On-demand backfill:**
- Scrolling to the bottom of cached content shows "Load older posts"
- Backfill fetches the next page of events (previous 30-day window) from the author's endpoint
- Media for backfilled posts is still lazy-loaded

**Background sync:**
- On app open: full sync (primary, reliable path)
- Android WorkManager: polling every 15 minutes, best-effort
- iOS Background App Refresh: at the OS's discretion, unreliable
- No push notifications — there is no server to send them

## Local Storage

### SQLCipher Database

Encrypted SQLite database. Key derived from a random 256-bit key stored in OS keychain.

**Tables:**

```sql
-- Your identity
CREATE TABLE identity (
    pubkey          TEXT PRIMARY KEY,
    private_key     BLOB NOT NULL,  -- stored in OS keychain, reference here
    feed_key        BLOB NOT NULL,  -- current feed key
    recovery_phrase TEXT,            -- encrypted, nullable (cleared after backup confirmed)
    created_at      INTEGER NOT NULL
);

-- People you follow
CREATE TABLE follows (
    pubkey          TEXT PRIMARY KEY,
    display_name    TEXT,
    avatar_hash     TEXT,
    connection_card TEXT NOT NULL,   -- JSON: pubkey + endpoints
    feed_key        BLOB NOT NULL,  -- their current feed key (encrypted by SQLCipher)
    last_synced_at  INTEGER DEFAULT 0,
    status          TEXT DEFAULT 'active'  -- active, blocked
);

-- Synced events (your own + from followed accounts)
CREATE TABLE events (
    id          TEXT PRIMARY KEY,
    pubkey      TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    kind        INTEGER NOT NULL,
    ref_id      TEXT,
    content     TEXT,
    media_refs  TEXT,       -- JSON array of MediaRef
    sig         BLOB NOT NULL,
    is_own      INTEGER DEFAULT 0,  -- 1 = your own post, never evicted
    fetched_at  INTEGER NOT NULL,
    last_viewed INTEGER
);
CREATE INDEX idx_events_feed ON events(created_at DESC);
CREATE INDEX idx_events_pubkey ON events(pubkey, created_at DESC);
CREATE INDEX idx_events_ref ON events(ref_id);

-- Cached media
CREATE TABLE media_cache (
    hash            TEXT PRIMARY KEY,
    path            TEXT NOT NULL,
    size            INTEGER NOT NULL,
    last_accessed   INTEGER NOT NULL
);

-- Pending follow requests (outbound)
CREATE TABLE outbound_follow_requests (
    pubkey          TEXT PRIMARY KEY,
    connection_card TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    status          TEXT DEFAULT 'pending'
);

-- Incoming follow requests
CREATE TABLE inbound_follow_requests (
    pubkey              TEXT PRIMARY KEY,
    encrypted_endpoints BLOB NOT NULL,
    created_at          INTEGER NOT NULL,
    status              TEXT DEFAULT 'pending'
);

-- Queued outbound events (comments/likes waiting to be delivered)
CREATE TABLE outbound_queue (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    target_pubkey   TEXT NOT NULL,
    event_blob      BLOB NOT NULL,
    created_at      INTEGER NOT NULL,
    retry_count     INTEGER DEFAULT 0
);
```

### Retention Policy

**Your own content**: Never evicted. You are the source of truth. Stored indefinitely.

**Other people's content (events)**: Retained for the sync window (default 30 days) plus a grace period. LRU eviction — recently viewed old content survives longer.

**Other people's content (media)**: Evicted more aggressively. LRU eviction when cache exceeds configurable limit (default 2GB). Posts with evicted media show a placeholder — tap to re-fetch if the author is reachable.

### Media Storage

- Photos stored as encrypted files in app's sandboxed directory
- Your own photos: original + compressed version (for serving to followers)
- Cached photos from others: compressed only
- All media encrypted at rest with the device-local key

## UI Screens

### Onboarding (first launch)
1. Welcome screen — "A social feed for your real friends. No ads. No algorithm. You own everything."
2. Generate keypair (automatic, brief animation)
3. Set display name + avatar (required — name only, avatar optional)
4. Show recovery phrase — "Write this down. It's the only way to recover your account."
5. Confirm backup (re-enter 3 random words)
6. Done — empty feed with prompt: "Add a friend to get started" + show your invite link/QR

### Feed
- Chronological, reverse-chronological list of posts from followed accounts
- Pull-to-refresh triggers sync
- Photos load lazily as posts scroll into view
- Tap post — full-screen photo + caption + comments/reactions
- Sync status: "Last synced: 5 min ago" / "Syncing..."
- Bottom of feed: "Load older posts" (explicit action, not infinite scroll)
- No algorithmic sorting, no ads, no explore, no suggested content

### Compose
- Launched from a compose **floating action button** (post-audit 2026-06-28; was the "Post" tab)
- Select photo from gallery or take with camera
- Add caption
- Actions sit in a **bottom action bar**: **Cancel** + **Next** (Next → Preview → Post). A photo is required to advance; a hint says so while it's missing.
- Photo is compressed, encrypted, signed, stored locally
- If relay configured: push to relay in background

### Profile (yours)
- Display name, avatar, bio
- Grid of your posts
- QR code button — shows your connection card QR
- Share button — copies invite link
- Follower count + following count
- Settings gear

### Profile (others)
- Display name, avatar, bio — resolved from the peer's latest **kind=2 profile event** (via `followProfileProvider` + `EncryptedAvatar`); the `follows` row carries no live name/avatar. The friends list resolves names/avatars the same way.
- Grid of their posts (from local cache)
- "Load older posts" to backfill
- Unfollow button
- Last synced timestamp
- Connection status: "Reachable" / "Last seen: 2 hours ago"

### Follow
- Scan QR code — parse connection card — send follow request
- Tap invite link — same flow
- Pending follows shown in a list
- Incoming follow requests: accept/reject

### Settings
- Recovery phrase (re-show)
- Relay configuration (Phase 2)
- Storage management (cache size, clear cache)
- Tor status (on/off, .onion address)
- Network status (peers reachable, sync stats)
- About / version

### Navigation (app shell)
Bottom tab bar with four destinations — **Feed · Friends · Rooms · You** — plus a compose **FAB** (hidden during a voice call). _(Post-audit 2026-06-28: replaced the earlier Feed/Friends/Post/You bar where "Post" was a modal action.)_ **Rooms** is the voice hub (Plan 16) — start a room + recent call history — promoted from a Friends app-bar icon to a top-level tab.

## Background Behavior

### iOS
- Background App Refresh: short sync burst when iOS grants time (~30s). Unreliable timing.
- No persistent background process — Tor and on-device server only run in foreground.
- No push notifications.
- **Primary sync path is app-open.** The UX is designed around this.

### Android
- WorkManager for periodic sync (minimum 15-minute interval). Subject to Doze mode.
- Optional foreground service (persistent notification) for keeping Tor + server alive in background. Makes the device a persistent endpoint but costs battery.
- No push notifications.

### Honest UX expectations
- Content arrives reliably when the app is open and the author (or their relay) is reachable
- Content may arrive in the background on Android (15-min polling or foreground service)
- Content will NOT arrive reliably in the background on iOS
- A spare-device relay makes your content available 24/7 regardless of your main phone being on
- The async model is intentional: this is not designed to be addictive or demand constant attention

## Tech Stack

- **Framework**: Flutter (Dart)
- **HTTP server**: `shelf` package
- **Database**: SQLCipher via `drift` with SQLCipher
- **Crypto**: libsodium via direct FFI
- **Tor**: Arti via FFI (Rust -> C -> Dart)
- **mDNS**: `multicast_dns` package
- **QR**: `mobile_scanner` (read) + `qr_flutter` (generate)
- **Serialization**: CBOR (`cbor` package)
- **Image**: `image` package for compression/resizing
- **State management**: Riverpod (`flutter_riverpod` + `riverpod_generator`)

## MVP Scope

Phase 1 — what ships first:
1. Identity generation + recovery phrase backup
2. Profile creation (name, avatar)
3. Post photos with captions
4. Invite links + QR code scanning for follow flow
5. Follow handshake with key exchange
6. LAN sync (mDNS discovery + local HTTP + manifest exchange)
7. Tor onion service for WAN sync
8. Chronological feed with lazy media loading
9. Encrypted local storage
10. Comments and reactions on posts
11. Feed key rotation on unfollow
12. Spare-device relay: turn an old phone into a personal always-on server

**Deferred to Phase 2**: Multi-device pairing, standalone Rust relay binary, direct WAN hole-punching, DMs, video, media cache management UI.

## Failure Modes

| Scenario | What happens | Mitigation |
|---|---|---|
| Alice posts, closes app. Bob opens later, Alice offline. | Bob doesn't get Alice's post until Alice (or her relay) comes online. | Transparent UX: "Waiting for Alice's device..." Spare-device relay solves this. The async model sets expectations correctly. |
| Two friends, rarely online at same time | Content delayed until overlap window. | Worst case for phone-only. Spare-device relay is the answer. LAN sync when physically together covers some of it. |
| Friend group of 10, most active daily | Someone with the latest posts is almost always reachable. Content propagates quickly. | Best case. Design for it. |
| New follower wants historical content | Only last 30 days sync automatically. | "Load older posts" on profile. Backfill fetches from author's endpoint in pages. |
| Author's media unreachable | Post shows in feed with placeholder. | "Tap to load when available." Media retried on next sync with author. |
