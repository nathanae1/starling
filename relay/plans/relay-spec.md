# Relay

The relay is an optional, zero-knowledge **store-and-forward** service that
makes an Owner's encrypted content available 24/7. It caches encrypted Events
and Media and serves them to the Owner's Followers over Tor when the Owner's
phone is offline. It never decrypts anything, and it never fetches, proxies,
or aggregates content across Owners.

The relay is **not required**. Starling works phone-to-phone. The relay is the
standalone tier of the self-hosting gradient (phone↔phone → standalone relay);
it solves the availability problem — your content is reachable even when your
phone is asleep — for anyone who already runs a Linux box.

> **Status.** This spec describes the shipped **R3** design (Plan 15). A prior
> revision described a single-owner relay with a spare-device phone mode and
> clearnet TLS; both were abandoned. See `app/plans/15-headless-relay.md` and
> `app/plans/15b-r3-multi-endpoint-decision.md` for the history.

## Architecture

A single Rust process embeds [Arti](https://gitlab.torproject.org/tpo/core/arti)
and hosts N Tor onion services on one `TorClient`:

- one **admin onion** serving only `POST /pair`;
- one **per-Owner onion** (its own HS keypair, generated at pair time) serving
  that Owner's read/write endpoints, reverse-proxied to a private loopback
  port.

Each Owner's Connection Card lists both the phone's onion and the relay's
onion (`Endpoint(type:'relay', address: …)`). Followers prefer a phone↔phone
path (LAN → libp2p-direct → the Owner's own onion) and fall back to the
relay's onion only when the phone is unreachable. No shared keys, no
OnionBalance, no descriptor coordination.

## Design principles

- **Zero-knowledge**: stores client-encrypted blobs it cannot decrypt. Sees
  only metadata (pubkey, ids, timestamps, sizes). The serving crates are
  mechanically barred from linking a content-AEAD crate
  (`starling-relay-http/tests/zero_knowledge.rs`).
- **Multi-owner**: one relay process hosts many independent Owners, each
  paired separately via single-use tokens. Storage is partitioned by
  `pubkey`; there is no aggregation or cross-Owner read.
- **Push-only ingest**: only the Owner (Ed25519 signature) can write. Anyone
  can read (the content is encrypted).
- **Stateless auth**: writes are authenticated per-request by an Ed25519
  signature — no sessions, no bearer tokens.

## API

Served on each Owner's per-Owner onion. Reads need no auth; writes require the
Owner signature headers below.

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| `GET` | `/status` | none | — | JSON `{pubkey, version, event_count, storage_used, storage_limit, media_storage_used}` |
| `GET` | `/manifest?since=&until=&until_id=` | none | — | CBOR `{pubkey, events:[{id,created_at}], has_older}` |
| `GET` | `/events?since=&since_id=` | none | — | CBOR `Envelope` of stored items; truncated pages carry the next keyset cursor in `extensions["next"]` |
| `GET` | `/media/<hash>` | none | — | raw `nonce‖ciphertext` blob (`application/octet-stream`) |
| `POST` | `/events` | owner-sig | CBOR `{items:[{id, payload, type?}]}` | `202` CBOR `{accepted, rejected}` |
| `POST` | `/events/delete` | owner-sig | CBOR `{ids:[...]}` | `200` CBOR `{deleted, missing}` |
| `POST` | `/media/<hash>` | owner-sig | raw encrypted blob | `202` |
| `POST` | `/media/delete` | owner-sig | CBOR `{hashes:[...]}` | `200` CBOR `{deleted, missing}`; `400` if any hash is malformed |
| `GET` | `/media-manifest?after=` | owner-sig | — | CBOR `{hashes, has_older}` |
| `POST` | `/unpair` | owner-sig | empty | `200`; the wipe runs ~0.5s later |

Admin onion: `POST /pair` only (see "Pairing").

**Paging.** `/manifest` and `/events` are keyset-paged: a client passes the
oldest returned `(created_at, id)` back as the cursor. `/events` also bounds
each page by cumulative payload bytes, so an anonymous read can never force
the relay to buffer an unbounded amount of RAM.

**Item types.** `POST /events` items carry an optional `type` (default
`"event"`). The relay stores and serves back whatever type it receives, so an
Envelope item type it does not understand still transits the relay tier
unchanged (preserve-and-forward). It never inspects an item's payload.

**Deletion.** All deletion *decisions* live on the phone (zero-knowledge:
the relay never learns whether an id died to a tombstone, a prune, or
anything else — only that its Owner asked). Both delete routes are
idempotent batch POSTs — absent ids/hashes count in `missing`, never an
error — and clients chunk requests to ≤500 items. Event deletes apply in
one transaction; media deletes remove rows first and unlink files
best-effort after commit (a crash in between leaves an orphan file for the
startup GC, never a row pointing at nothing). There is **no** relay-side
TTL or admin-UI "reclaim space": the relay only ever deletes what the
Owner's phone explicitly names (unpair remains the whole-account wipe).

**Wire unpair.** `POST /unpair` lets the Owner's phone end the pairing over
the wire: the relay wipes the Owner (row + media + onion) exactly like an
admin-UI unpair, so relay-primary Followers' probes fail fast and they fall
back to the phone. The handler answers `200` first and runs the wipe after a
short grace period — the wipe aborts the very task serving the request, and
tearing it down inline would reset the connection before the response
flushes (making every successful unpair look like a transport failure to
the phone). The phone treats the call as best-effort: local unpair never
waits on it, and its heal pass retries only transport-level failures.

**Not implemented** (phone-to-phone only, per "follows/config on phones"):
`follow-request` and `follow-accept`. A Follower that needs a feed-key
rotation, or wants to send a follow request, reaches the Owner's phone
directly.

### Authentication

Write endpoints require:

```
X-Starling-Pubkey: base64(owner_pubkey)         # raw 32-byte Ed25519 key
X-Starling-Ts:     <unix seconds>               # request-bound scheme
X-Starling-Sig:    base64(Ed25519.sign(sk, digest))
```

where, for the current **request-bound** scheme,

```
digest = BLAKE2b-256("starling-owner-req-v1" ‖ method ‖ path
                     ‖ u64_be(unix_ts) ‖ BLAKE2b-256(body))
```

Binding the method, path, and timestamp stops a captured signature from being
replayed against another route or reused indefinitely; the relay rejects a
timestamp more than 10 minutes off its clock. For one release the relay also
accepts the **legacy** scheme (no `X-Starling-Ts`, signature over
`BLAKE2b-256(body)` only) so phones and self-hosted relays can update out of
step. The relay verifies the pubkey matches the onion's configured Owner
(`403` on mismatch, `401` on a bad/missing/stale signature).

## Storage

- **SQLite** (`rusqlite` + `r2d2`, WAL) for owners, pending pairings, and
  served event metadata. No SQLCipher — payloads are already client-encrypted.
- **Filesystem** for media blobs, namespaced per Owner and hash-sharded:
  `media/<owner_hex>/<h[0:2]>/<h[0:4]>/<hash>`. Per-Owner namespacing is what
  stops two Owners pushing different ciphertext under the same plaintext hash
  from clobbering each other.

### Schema (`crates/starling-relay-storage/migrations/`)

```sql
CREATE TABLE paired_owners (
    pubkey               BLOB PRIMARY KEY NOT NULL,   -- 32-byte Ed25519 pubkey
    label                TEXT,
    paired_at            INTEGER NOT NULL,
    relay_onion_address  TEXT NOT NULL,               -- this Owner's relay onion
    local_port           INTEGER NOT NULL UNIQUE,     -- loopback port Arti proxies to
    storage_cap_bytes    INTEGER                       -- NULL → per_owner_default
);

CREATE TABLE pending_pairings (
    token        BLOB PRIMARY KEY NOT NULL,           -- 32 random bytes
    created_at   INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    consumed_at  INTEGER,                              -- NULL until claimed
    created_by   TEXT NOT NULL,                        -- 'web' | 'cli'
    label        TEXT
);

CREATE TABLE served_events (
    pubkey      BLOB NOT NULL,
    id          TEXT NOT NULL,                         -- plaintext event id (Crockford b32)
    created_at  INTEGER NOT NULL,
    msg_seq     INTEGER NOT NULL,
    nonce       BLOB NOT NULL,
    payload     BLOB NOT NULL,                         -- raw EncryptedEvent CBOR
    size        INTEGER NOT NULL,                      -- payload bytes (cap accounting)
    item_type   TEXT NOT NULL DEFAULT 'event',         -- Envelope item type (F4)
    PRIMARY KEY (pubkey, id),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);

CREATE TABLE served_media (
    pubkey     BLOB NOT NULL,
    hash       TEXT NOT NULL,                          -- 64-char lowercase hex BLAKE2b-256
    size       INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    path       TEXT NOT NULL,                          -- relative to media_dir
    PRIMARY KEY (pubkey, hash),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);

CREATE TABLE admin_credentials (         -- argon2id; only present after set-password
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    password_hash TEXT NOT NULL,
    updated_at    INTEGER NOT NULL
);
```

Unpair = `DELETE FROM paired_owners WHERE pubkey = ?`; the FK cascade wipes
that Owner's events and media rows, the Owner's blob directory is removed, and
the `RunningOnionService` is dropped (Arti unpublishes the descriptor).

### Startup media GC

On boot, before any Owner router is serving (so the sweep races nothing),
the relay reconciles `served_media` against the filesystem:

1. **Unknown-owner dirs** are removed (heals an unpair that crashed after
   the DB delete but before `remove_dir_all`).
2. **Orphan files** — including stray `.tmp`s — with no `served_media` row
   are unlinked (heals a crashed push or a delete that committed its row
   removal but died before the unlink).
3. **Rows whose file is missing** are dropped, freeing the phantom bytes
   they pinned in cap accounting; the hash disappears from
   `/media-manifest`, so the phone's reconcile re-pushes the blob —
   a served-404-forever heals itself.

### Storage caps

- `per_owner_default_cap_bytes` (per Owner) and `disk_cap_bytes` (host-wide)
  bound usage; `0` means unlimited. Usage counts **event payloads + media
  blobs combined**.
- The cap is checked at one accounting chokepoint inside the same transaction
  as the write, so two concurrent pushes cannot both pass against a stale
  baseline.
- When a cap would be exceeded, `POST /events` and `POST /media` return
  `507 Insufficient Storage`. `/status` reports `storage_used` and
  `storage_limit` so the phone can predict a 507 before pushing.

## Pairing

The admin onion (nickname `starling-relay-admin`, persisted in Arti's
keystore) exposes the admin web UI (on `bind_admin`, loopback by default) and
`POST /pair` over Tor.

1. Operator opens the web UI or runs `starling-relay pair --label X`. The relay
   mints a single-use `pending_pairings` token (TTL `pairing_token_ttl_seconds`)
   in one transaction that invalidates any prior unconsumed token, and renders
   a QR encoding `starling-relay://pair?card=base64url(CBOR{admin_onion,
   pairing_token, relay_version})`.
2. The phone builds
   `claim = BLAKE2b-256("starling-relay-pair-v1" ‖ owner_pubkey ‖ admin_onion ‖ token)`,
   signs it, and `POST /pair`s CBOR `{owner_pubkey, pairing_token, sig}` over
   Tor.
3. The relay verifies the signature, atomically claims the token (`409` if
   already used, `410` if expired, `401` on bad sig), allocates a free loopback
   port, generates a fresh HS keypair for this Owner, launches the onion,
   persists `paired_owners`, and returns `200` CBOR `{relay_onion, relay_id}`.
4. The phone adds `Endpoint(type:'relay', address: relay_onion)` to its
   Connection Card and fans the updated Card to Followers via the Plan 13
   `pending_card_distributions` channel.

A captured token is useless without the Owner's signing key — the signature
binds `owner_pubkey` to `(admin_onion, token)`.

## Configuration (`/etc/starling-relay/config.toml`)

```toml
data_dir                    = "/var/lib/starling-relay"
bind_admin                  = "127.0.0.1:8088"   # loopback default; set a password before LAN exposure
disk_cap_bytes              = 5368709120         # 5 GiB host-wide (0 = unlimited)
per_owner_default_cap_bytes = 1073741824         # 1 GiB per Owner  (0 = unlimited)
log_level                   = "info"
pairing_token_ttl_seconds   = 600
local_port_range            = [17000, 17999]     # per-Owner loopback ports
```

Every field is overridable with `STARLING_RELAY_<UPPER_SNAKE>`. Unparseable
numeric overrides, unknown TOML keys, and out-of-range values fail loudly at
startup rather than silently keeping a default. Arti's data directory is
`${data_dir}/arti/`. `SIGTERM` shuts down gracefully.

## Deployment

- **Docker:** `docker build -f relay/docker/Dockerfile -t starling-relay .`
  (multi-stage → distroless, runs as uid 65532). Add a restart policy
  (`--restart unless-stopped`) — the release build is `panic = "abort"` and
  distroless does not restart on its own.
- **systemd/Debian:** `relay/scripts/install-debian.sh`
  (`relay/systemd/starling-relay.service`, `Restart=on-failure`, hardened).
- **Proxmox LXC:** `relay/scripts/proxmox-install.sh`.
- Tor-only. Clearnet TLS ingress is deferred (v2); there is no `listen_addr`,
  `tls_cert`, or Windows/macOS target — the binary is Linux/unix.

## Security considerations

- All data is client-encrypted — a relay compromise leaks only metadata
  (pubkeys, ids, timestamps, sizes), never plaintext or feed keys.
- Each paired relay holds its own HS identity key per Owner. A compromised
  relay can answer for that relay's `.onion` and exposes the encrypted cache
  stored there; the Owner's other endpoints (phone, other relays) are
  unaffected, and it still cannot decrypt content. Mitigation: the Owner
  unpairs, re-signs the Card without that endpoint, and fans the update to
  Followers.
- Owner writes are Ed25519-signed and request-bound (method/path/timestamp),
  preventing unauthorized writes and cross-route/replay reuse of a captured
  signature.
- Anonymous reads and owner-signed writes use separate rate-limit buckets, so
  a read flood cannot starve the Owner's own pushes.
- The admin UI is loopback-bound by default; LAN exposure requires an argon2id
  password. The CLI control channel is a `0700`-parent Unix socket.

## Cross-language enforcement

The relay (Rust) and app (Dart) share the wire protocol, not code. Agreement
is enforced by byte-pinned shared vectors in
`app/starling/test/vectors/index.json`, asserted on the Dart side by
`test/vectors/vectors_test.dart` and on the Rust side by
`crates/starling-wire/tests/wire_vectors.rs` — Dart-produced surfaces are
decoded in Rust, Rust-produced surfaces are encode-pinned. Covered surfaces:
Crockford base32; the pairing claim (digest, sig, CBOR); `relay_id`;
`PairResponse`; the QR card; `EncryptedEvent`; `PushBatch` + owner sig;
`PushReceipt`; `ManifestPage`; `MediaManifestPage`; the `/events` Envelope.
