# Protocol Specification

The protocol is the contract between all Starling components. It defines how events are structured, encrypted, signed, synced, and versioned. Both the app and relay implement this spec.

## Event Format

### Plaintext Event (before encryption)

```
Event {
  version:    string       // date-based, e.g. "2026-03-24"
  id:         string       // blake2b-256(cbor(version + pubkey + created_at + kind + ref + content + media + extensions))
  pubkey:     string       // creator's Ed25519 public key
  created_at: uint64       // unix timestamp (seconds)
  kind:       uint8        // event type (see below)
  ref:        string?      // optional, references another event id
  content:    bytes        // kind-specific payload (see below)
  media:      MediaRef[]   // for posts with photos
  extensions: Map<string, bytes>  // optional, included in ID hash (empty map if none)
  sig:        bytes        // Ed25519 signature over id
}

MediaRef {
  hash:       string       // BLAKE2b-256 of plaintext media blob
  mime_type:  string       // e.g. "image/jpeg"
  size:       uint64       // plaintext size in bytes
}
```

### Event Kinds

Event kinds are an open enum. Clients MUST store and sync events with unknown kinds without crashing or dropping them. Unknown kinds are preserved in the database and forwarded during sync, but not rendered in the UI. This allows older clients to coexist with newer ones in a P2P network where forced upgrades are impossible.

**Reserved ranges:**

| Range | Category | Description |
|-------|----------|-------------|
| 1-9 | Core social feed | Posts, profiles, follows, comments, likes, deletes |
| 10-19 | Real-time / ephemeral | Voice rooms, typing indicators, presence |
| 20-99 | Reserved | Future core protocol extensions |
| 100-199 | Messaging | DMs, group chat, read receipts |
| 200-299 | Media | Video, audio, file sharing |
| 300+ | Application-defined | Third-party extensions |

**Defined kinds (v1):**

| Kind | Name | Content | Ref |
|------|------|---------|-----|
| 1 | Post | Caption text (UTF-8) | -- |
| 2 | Profile | JSON: `{ name, bio, avatar_hash }` | -- |
| 3 | Follow List | JSON array of pubkeys | -- |
| 4 | Comment | Comment text (UTF-8) | Target post id |
| 5 | Like | Empty | Target post id |
| 6 | Delete | Empty | Target event id |

### Encrypted Event (what gets stored/transmitted)

```
EncryptedEvent {
  pubkey:     string       // plaintext -- needed for routing
  created_at: uint64       // plaintext -- needed for sync queries
  nonce:      bytes[24]    // random, unique per event
  payload:    bytes        // XChaCha20-Poly1305(feed_key, nonce, serialize(Event))
}
```

### Serialization

- Events are serialized to CBOR before encryption
- The `id` is computed as BLAKE2b-256 over the CBOR-serialized ID fields: `version`, `pubkey`, `created_at`, `kind`, `ref`, `content`, `media`, `extensions` (excluding `id` and `sig`)
- `version` is included in the ID hash to prevent downgrade attacks (replacing the version tag to trigger different parsing)
- `extensions` is included in the ID hash so item-level extensions are inside the signature by default (see Envelope Trust Model below). Pass an empty map `{}` when no extensions are present — the hash must be deterministic regardless of whether extensions exist.
- The `sig` is computed as Ed25519.sign(private_key, id_bytes)
- CBOR decoders MUST preserve unknown fields on decode, not drop them. This prevents old clients from silently stripping data added by newer protocol versions.

## Encryption Scheme

### Key Hierarchy

```
Identity Key (Ed25519 keypair)
  |
  +-- X25519 conversion (for Diffie-Hellman key exchange)
  |
  +-- Feed Key (XChaCha20-Poly1305 symmetric key, 256-bit)
       +-- encrypts all events + media blobs
```

### Feed Key Management

- Creator generates a random 256-bit feed key (epoch 0) at identity creation
- Feed key is shared with each follower individually:
  1. Convert both parties' Ed25519 keys to X25519
  2. Perform X25519 Diffie-Hellman to derive shared secret
  3. `crypto_kdf_derive_from_key(subkey_len=32, subkey_id=1, ctx="starlingkex", key=shared_secret)` using libsodium's BLAKE2b-based KDF, with `info = requester_pubkey || responder_pubkey || timestamp` to ensure unique keys per exchange
  4. Encrypt feed key with derived key, send to follower
- On follower removal: generate new feed key, re-encrypt for all remaining followers, distribute on next sync

### Feed Key Ratchet (MegOLM-style)

Feed keys advance forward using a hash ratchet to provide forward secrecy for new followers:

```
epoch_key_0 = random 256-bit key (generated at identity creation)
epoch_key_1 = BLAKE2b-256(epoch_key_0 || "starling-ratchet-v1")
epoch_key_2 = BLAKE2b-256(epoch_key_1 || "starling-ratchet-v1")
...
epoch_key_n = BLAKE2b-256(epoch_key_{n-1} || "starling-ratchet-v1")
```

**How it works:**
- Each encrypted event includes the epoch number it was encrypted with (stored in the EncryptedEvent alongside existing fields)
- The owner advances the epoch periodically (e.g., daily or every N posts — implementation decides)
- When sharing keys with a new follower, the owner sends the **current** epoch key. The follower can derive all future keys but **cannot derive past keys** (the hash is one-way)
- To grant a new follower access to history, the owner optionally sends older epoch keys during the follow handshake
- On unfollow: force-advance to a new random epoch key (not derived from the chain), breaking the ratchet for the removed follower

**Security properties:**
- A new follower cannot read posts from before they were granted access (unless explicitly given old keys)
- A removed follower cannot read posts after the epoch advances past the unfollow point
- A compromised epoch key only exposes content from that epoch forward until the next random re-key

**EncryptedEvent update:**
```
EncryptedEvent {
  pubkey:     string       // plaintext — needed for routing
  created_at: uint64       // plaintext — needed for sync queries
  epoch:      uint32       // feed key epoch number
  msg_seq:    uint64       // per-message key sequence within the epoch (MegOLM-shaped)
  nonce:      bytes[24]    // random, unique per event
  payload:    bytes        // XChaCha20-Poly1305(msg_key, nonce, serialize(Event))
}
```

`msg_seq` is carried in cleartext so a receiver (and the relay) can index by
it without decrypting. The per-message AEAD key is derived as
`BLAKE2b-256(chainRoot ‖ "starling-msg-key-v1" ‖ u64_be(msg_seq))`, so
`(epoch, msg_seq)` together select the key; the relay stores `msg_seq`
alongside `created_at` but never derives a key.

### Nonce Generation

All nonces are 24 bytes generated by a cryptographically secure random number generator. Nonces are NEVER derived from content hashes or any deterministic source. This prevents nonce reuse if the same content is encrypted multiple times.

- Event encryption: random 24-byte nonce, stored in EncryptedEvent.nonce
- Media encryption: random 24-byte nonce, prepended to the encrypted blob
- Feed key encryption (during key exchange): random 24-byte nonce, sent alongside the encrypted feed key

### Media Encryption

- Each media blob is encrypted independently with the feed key
- Nonce: random 24 bytes (prepended to output)
- Encrypted blob format: `nonce (24 bytes) || XChaCha20-Poly1305(feed_key, nonce, plaintext_blob)`
- The MediaRef.hash in the event references the plaintext BLAKE2b-256 hash, so followers can verify integrity after decryption

## Envelope Format & Trust Model

### Structure

The Envelope is the unit that transports move. All sync, push, and real-time communication operates on Envelopes, not on bare EncryptedEvents.

```
Envelope {
  version:    string              // protocol version, e.g. "2026-03-24"
  items:      EnvelopeItem[]      // one or more typed items
  extensions: Map<string, bytes>  // optional, UNTRUSTED (see trust model)
}

EnvelopeItem {
  type:       string              // "event", "commit", "receipt", etc.
  payload:    bytes               // type-specific content
  extensions: Map<string, bytes>  // optional, trust governed by item type's rules
}
```

**Defined item types (v1):**

| Type | Payload | Integrity mechanism |
|------|---------|-------------------|
| `"event"` | Serialized EncryptedEvent | Ed25519 signature over Event ID (inside the encrypted payload) |

Future item types (MLS commits, delivery receipts, etc.) will be added as new type strings. Old clients that encounter unknown item types MUST preserve and forward them during sync, not drop them.

### Trust Model

**Rule 1: Every item carries its own integrity mechanism, defined by its type.**

The item type's specification answers "how do I know this is authentic?" Events carry Ed25519 signatures. When MLS is added, MLS commits will carry MLS's own authentication. Any new item type (receipts, read markers, etc.) MUST define its signing or authentication scheme before shipping. An item type without a defined integrity mechanism is a protocol bug.

**Rule 2: The Envelope itself is not signed and is not trusted.**

A receiver treats an Envelope as an untrusted container: parse it, extract items, verify each item independently using the item type's integrity mechanism, then discard the Envelope. Any field that lives on the Envelope rather than inside an item is a hint, not a claim. The `version` field on the Envelope tells the parser how to decode — it does not assert authenticity.

**Rule 3: Envelope-level extensions are explicitly untrusted.**

If future work wants to put something security-relevant in an Envelope extension, this rule forces a decision: either promote it to a proper item type with its own signing scheme, or accept that it's advisory-only. This is the guardrail that prevents "forgot to think about trust" bugs. Envelope extensions are for transport-layer hints (routing preferences, compression flags, etc.) — never for content or identity claims.

**Rule 4: Item-level extensions are governed by the item type's rules.**

If an item type signs its payload, extensions on that item are either inside the signed bytes (trusted) or outside (untrusted), and the item type's specification MUST declare which. The default is: **extensions are inside the signature**. This is the safer default — it forces the "untrusted extension" case to be an explicit, documented decision rather than an accidental omission.

For Events specifically: the `extensions` field is included in the Event ID hash (and therefore inside the Ed25519 signature). Any extension added to an Event is authenticated. An unsigned Event extension is not possible without changing the Event spec — by design.

## Sync Protocol

All sync happens over HTTP. The same API is implemented by:
- The phone's on-device server (LAN / Tor onion)
- The relay server (HTTPS or Tor onion)

### Endpoints

**GET /manifest?since={timestamp}&until={timestamp}**
- Returns a lightweight list of event IDs and timestamps
- Response: CBOR `{ pubkey, events: [{ id, created_at }], has_older: bool, connection_card_update?: ConnectionCardUpdate }`
- Used by the requester to determine which events they're missing
- The optional `connection_card_update` field carries the Owner's latest Connection card to a specific Follower when the Owner has changed endpoints (e.g., added a Relay). The Follower verifies the embedded signature against the Owner's pubkey (known from their `Follow` row) and replaces their stored card. The next `/manifest` request acks the update by including the new card's `created_at` in a `card_seen_at` query parameter; the server clears the pending distribution row on ack.

```
ConnectionCardUpdate {
  card:       ConnectionCard   // full updated Connection card
  sig:        bytes             // Ed25519.sign(owner_sk, blake2b_256(cbor(card) || u64_be(created_at)))
  created_at: uint64            // when the Owner authored this update
}
```

Trust model: this is an Envelope-style transport hint, but signed. Followers MUST verify the signature before applying the update. An unsigned or invalid-sig card update MUST be discarded — the server is treated as an untrusted relay even when it is the Owner's own phone. Replay is bounded by `created_at`: a Follower ignores updates with `created_at <=` the one they last applied.

**GET /events?since={timestamp}&since_id={id}**
- Returns the owner's events at/after the `(since, since_id)` keyset cursor
- Response: CBOR **Envelope** of `type:"event"` items (each item's `payload`
  is a serialized EncryptedEvent) — NOT a bare array. Pages are bounded by
  count and cumulative bytes; a truncated page carries the next cursor in the
  Envelope's `extensions["next"]` (`{created_at, id}`)
- Only returns events from that server/onion's owner

**GET /media/{blake2b_hash}**
- Returns the encrypted media blob (nonce prepended)
- Response: raw bytes
- Content-Type: `application/octet-stream`

**GET /status**
- Returns server info
- Response: JSON `{ pubkey, version, event_count, storage_used, storage_limit, media_storage_used }`
  - `storage_used`: total bytes stored for this owner (event payloads + media) — the figure the cap and `507` threshold actually count
  - `storage_limit`: the owner's cap in bytes, or `0` for unlimited
  - `media_storage_used`: media-only bytes; retained for older clients, superseded by `storage_used`
- No authentication required

**POST /follow-request**
- Send a follow request to the account owner
- Body: CBOR `{ requester_pubkey, encrypted_return_endpoints, nonce }`
- `encrypted_return_endpoints`: the requester's connection card, encrypted with X25519 DH shared key
- The owner's device queues this and processes it (accept/reject) on next open

**POST /follow-accept**
- Owner sends back the encrypted feed key to the requester
- Body: CBOR `{ owner_pubkey, encrypted_feed_key, nonce }`
- `encrypted_feed_key`: the feed key encrypted for the requester's X25519 key
- Sent to the requester's endpoint

### Relay-Only Endpoints

The relay is multi-owner and Tor-only; each owner is served on its own onion.
See `relay/plans/relay-spec.md` for the full surface (`/pair`,
`/media-manifest`, storage caps). `follow-request` / `follow-accept` are NOT
relay endpoints — they are phone-to-phone.

**POST /events** (relay only)
- Owner pushes its own new events to its relay
- Body: CBOR `{ items: [{ id, payload, type? }] }` (a PushBatch, NOT a bare
  array); `payload` is a serialized EncryptedEvent, `type` defaults to
  `"event"` and is preserved so unknown item types transit the relay
- Response: `202` CBOR `{ accepted, rejected }`
- Owner-signed (see below)

**POST /media/{blake2b_hash}** (relay only)
- Owner pushes one encrypted media blob (raw `nonce‖ciphertext` body, keyed by
  the path hash), NOT a multipart upload
- Response: `202`
- Owner-signed

**POST /events/delete** and **POST /media/delete** (relay only)
- Owner withdraws stored events/media by plaintext id / hash. All deletion
  decisions live on the phone (tombstones, prune horizon); the relay never
  learns why an id dies
- Body: CBOR `{ ids: [...] }` / `{ hashes: [...] }`, chunked ≤500 per request
- Response: `200` CBOR `{ deleted, missing }` — idempotent, absent items count
  as `missing`; `/media/delete` is `400` if ANY hash is malformed
- Owner-signed

**POST /unpair** (relay only)
- Owner ends the pairing over the wire: the relay wipes the owner's stored
  data and drops its onion, so relay-primary Followers fall back to the
  phone instead of probing a stale endpoint forever
- Body: empty
- Response: `200`; the wipe itself runs after a short grace so the response
  flushes before the serving task is torn down
- Owner-signed; best-effort on the phone side (local unpair never depends
  on it — a heal pass retries transport failures)

### Sync Handshake

Before syncing events, a version check occurs:

```
Client -> Server: GET /status
Server -> Client: { version: "2026-03-24", ... }
```

If the client supports the server's version, sync proceeds. If not, the client skips this account and warns the user to update.

### Authentication (Relay Push)

Owner-signed relay endpoints (`POST /events`, `POST /media/{hash}`,
`POST /events/delete`, `POST /media/delete`, `GET /media-manifest`,
`POST /unpair`) require
signature headers. The current
**request-bound** scheme binds the method, path, and a timestamp so a
captured signature can't be replayed against another route or reused
indefinitely:

```
X-Starling-Pubkey: base64(pubkey)              // raw 32-byte Ed25519 key
X-Starling-Ts:     <unix seconds>
X-Starling-Sig:    base64(Ed25519.sign(sk, digest))
  digest = blake2b_256("starling-owner-req-v1" || method || path
                       || u64_be(ts) || blake2b_256(request_body))
```

For one release the relay also accepts the **legacy** scheme (no
`X-Starling-Ts`, signature over `blake2b_256(request_body)` only). It rejects
a timestamp more than 10 minutes off its clock, verifies the pubkey matches
that onion's owner (`403` on mismatch), and `401`s a bad/missing/stale
signature.

## Connection Card

Encodes everything needed to reach an account:

```
{
  pubkey: "base32_ed25519_public_key",
  endpoints: [
    { type: "onion", address: "abc123...xyz.onion" },
    { type: "relay", address: "relay456...xyz.onion" }
  ],
  capabilities: ["pairwise-v1"]
}
```

Every endpoint is `{ type, address }`. The relay endpoint is a Tor
`.onion` (the relay is Tor-only in v1), NOT a clearnet URL; Followers rank it
below every phone↔phone tier and use it only when the phone is unreachable.

The `capabilities` field advertises what the peer supports. v1 clients advertise `["pairwise-v1"]`. Future capabilities (e.g., `"mls-v1"`, `"media-streaming-v1"`) are added as they ship. During handshake, peers compute the intersection of capabilities to determine which protocols to use. Peers with no `capabilities` field are assumed to be pre-v1 and treated as `["pairwise-v1"]`.

- Serialized as CBOR, then base64url-encoded for QR codes and links
- QR code contains: `starling://connect?card={base64url_encoded_card}`
- Share link: `https://starling.link/connect?card={base64url_encoded_card}` (deeplinks to app)

## Hole-Punch Signaling (via Tor)

When two peers connect via Tor, they can attempt to upgrade to a direct WAN connection:

1. Requester connects to the target's `.onion` address
2. Both peers discover their own public IP:port via STUN (using configurable STUN servers, defaulting to well-known public servers)
3. Peers exchange their public IP:port over the Tor connection (small payload, latency acceptable)
4. Both attempt simultaneous TCP or UDP open to each other's public endpoint
5. If hole-punch succeeds: subsequent data (event/media fetches) flows over the direct connection
6. If hole-punch fails: all data flows over Tor as fallback

This is an optimization, not a requirement. The sync protocol works identically over Tor or a direct connection — hole-punching just reduces latency for the data transfer phase.

**STUN servers:** The app ships with a default list of public STUN servers (e.g., Google, Cloudflare). Users can configure their own. The STUN server learns the device's public IP (which it already sees from the connection) but nothing about Starling, content, or identity. This is the only interaction with external infrastructure and it's optional — Tor-only mode works without it.

## Versioning

- Every event carries a `version` string (date-based, e.g. `"2026-03-24"`)
- The `/status` endpoint reports the server's protocol version
- Clients MUST handle unknown event kinds gracefully (skip, don't crash)
- Clients MUST handle events from newer versions gracefully (skip unknown fields)
- Breaking changes get a new version date; additive changes may reuse the same version

## Test Vectors

The protocol is enforced across implementations (Dart app, Rust relay, future clients) by shared test vectors, not by a schema language. Test vectors are the source of truth for wire format agreement.

### Vector format

Vectors live in a single self-describing file,
`app/starling/test/vectors/index.json`, built by
`test/vectors/vectors_builder.dart`. Each entry inlines its bytes as hex
(there are no separate per-type `.cbor` files). Byte-pinned surfaces store
the expected `cbor_hex` (and, for signed ones, the digest + signature hex);
decode-only surfaces store the expected decoded fields.

Regeneration is diff-asserting, not copy-paste: `vectors_gen.dart` rebuilds
every vector from the production encoders on every test run and FAILS when
`index.json` no longer matches. After an intentional wire change, run
`STARLING_WRITE_VECTORS=1 flutter test test/vectors/vectors_gen.dart` and
commit the diff.

The Dart harness (`test/vectors/vectors_test.dart`) and the Rust harness
(`relay/crates/starling-wire/tests/wire_vectors.rs`) both read this file:
Dart-produced surfaces are decoded and checked in Rust, Rust-produced surfaces
are byte-pinned. Both version constants (`kStarlingProtocolVersion`,
`PROTOCOL_VERSION`) pin to the single `protocol_version` entry, so a
one-sided bump fails the other side's tests. The `http` section additionally
pins the HTTP layer — method, path, query-param names, auth headers, and
success status per relay endpoint — asserted client-side by
`test/vectors/http_vectors_test.dart` and server-side (including query-param
*effect*) by `relay/crates/starling-relay-http/tests/http_vectors.rs`. This
is the source of truth for wire agreement — the specs are prose that can
lag; the vectors cannot.

### What vectors cover

1. **Event serialization**: Event fields → CBOR bytes → decode → fields match
2. **Event ID computation**: Given specific fields (including version and extensions), the ID hash is exactly these bytes
3. **Signing**: Given this keypair and this event, the signature is exactly these bytes
4. **Encryption**: Given this feed key and this nonce, the EncryptedEvent payload is exactly these bytes
5. **Envelope**: Given these items, the Envelope CBOR is exactly these bytes
6. **Key derivation**: Given this seed, the Ed25519 keypair is exactly this. Given this keypair, the X25519 conversion is exactly this.
7. **Feed key ratchet**: Given epoch key N, epoch key N+1 is exactly this

Vectors pin the protocol against future refactors: when you optimize the encoder, vectors tell you whether bytes already on users' devices still decode correctly. For a P2P system with no forced upgrades, this is how you avoid bricking people's data.
