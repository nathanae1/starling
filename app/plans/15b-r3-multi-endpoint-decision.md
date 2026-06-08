# Plan 15b — Topology decision: multi-endpoint Connection Card (R3)

Resolves the architectural open question raised after the 15a spike. Plan
15's "shared HS key, one master `.onion` per Owner via OnionBalance v3"
design doesn't survive contact with OB v3's actual key model (master key
exclusively on the OB instance, backend instances have independent keys —
two parties cannot republish for the same v3 onion without descriptor-
replacement wars). This doc replaces that topology with R3.

## The decision

- **Each node has its own HS keypair.** Phone's existing onion stays the
  phone's. Each Owner's paired relay generates its own onion at pair time.
- **No shared keys. No OnionBalance. No master/backend split.**
- **Owner's Connection Card carries multiple endpoints.** The wire shape
  already supports this — `ConnectionCard.endpoints` is a list of
  `Endpoint(type, address)` (see
  `app/starling/lib/models/connection_card.dart:6-35`).
- **Followers prefer a phone↔phone path; the relay is the last resort.**
  `PeerReachabilityMonitor._priority` ranks LAN → libp2p-direct → the
  Owner's own onion (`type == 'onion'`) → relay (`type == 'relay'`), and
  selects the first transport the background probe loop has marked
  reachable. So the relay onion only wins when every phone↔phone tier is
  unreachable (phone asleep/offline). This keeps content fresh (the relay
  v1 can't serve feed-key rotations) and avoids leaking Follower access
  patterns to the always-on box. See
  `app/starling/lib/sync/peer_reachability_monitor.dart:117` (`_priority`)
  and `:218,464`.
- **Card update on pair fans out via the existing
  `pending_card_distributions` machinery.** The table's doc comment
  literally calls out this case verbatim:
  *"When the Owner adds (or rotates) a Relay endpoint the phone signs the
  new card and writes one row per existing Follower. The row is consumed
  lazily: the manifest handler attaches the latest undelivered row to the
  Follower's next `/manifest` response."*
  (`app/starling/lib/services/storage/tables/pending_card_distributions_table.dart`)
- **Relay endpoint type stays distinct from phone-onion type** —
  `Endpoint(type:'relay', address: <onion>)`. Keeps the existing
  reachability-monitor branches and matches the Owner's mental model
  ("my phone" vs "my always-on box"). Wire format is identical; the
  type tag is a hint.

## What disappears from Plan 15

- §"Architecture overview" — entire diagram + OnionBalance prose.
- §"Pairing flow" §"HS identity key transfer / wrap_key / wrapped_hs_key"
  — all gone. The phone never sends its HS key anywhere; the relay
  generates its own.
- §"Crate / process layout" — collapses from **three processes
  (Rust + C-tor + OnionBalance under supervisord)** to **one process:
  the Rust binary with Arti embedded.**
- `starling-relay-tor` crate — gone. The relay uses `starling-arti`
  (extracted from `starling_bridge/src/arti/inner.rs`) the same way the
  phone does. The crate `starling-arti` already needs to support
  launching multiple onion services with distinct nicknames — verify
  `arti_client::TorClient::launch_onion_service` is callable N times on
  one `TorClient` (per docs, the nickname identifies the service, so
  N calls with N nicknames yields N services).
- `starling-relay-onionbalance.service` systemd unit, OnionBalance
  Python dep, OnionBalance config-rewriting code — all gone.
- Docker supervisord wrapper — gone. Single-process container (or
  `tini` for signal handling, but that's it).
- C-tor + tor-user account in install scripts — gone.
- `paired_owners.onion_address` / `hs_key_path` columns — collapse. The
  relay owns the HS key for each paired Owner via Arti's keystore; no
  separate path tracking. Schema becomes just `(pubkey, label, paired_at,
  relay_onion_address, local_port, storage_cap_bytes)`.
- `wrapped_hs_key` / `nonce` / HKDF over pairing token — gone from
  `/pair` body. Pairing claim is just `{owner_pubkey, pairing_token, sig}`.
- §"Spec amendment" line on §"Security Considerations" — the "phone's HS
  key on both sides" sentence is wrong under R3. Replace with: each
  paired relay has its OWN HS key. Compromise of a relay exposes that
  relay's content cache (zero-knowledge — still encrypted), and lets
  the attacker answer for the relay's `.onion`. The phone's `.onion` is
  untouched. Mitigation under compromise: Owner unpairs the relay, phone
  signs a new Card without that endpoint, fans it out via
  `pending_card_distributions`. No HS key rotation, no `.onion` change
  on the phone side.
- Spike 15a — its conclusion ("phone generates the HS keypair itself")
  is no longer required by Plan 15. Still desirable independently for
  general Arti-state durability (recover `.onion` after wiping Arti
  state), but downgraded from blocker to nice-to-have.

## What stays / changes from Plan 15

| Plan 15 element | Status under R3 |
|---|---|
| `starling-arti` workspace crate (extract from bridge) | **Keep**, but it's now the *only* Tor implementation — same crate runs on phone (via FFI) and relay (direct). |
| `starling-wire` crate (CBOR types, sig verify) | Keep. `PairingClaim` shrinks. |
| `starling-relay-storage` crate + multi-owner SQLite | Keep. `paired_owners` schema simplifies (no `hs_key_path`). |
| `starling-relay-http` crate (per-Owner axum router, sig middleware) | Keep, unchanged. |
| `starling-relay-admin` crate (web UI, /pair page, QR, /login, /health) | Keep, unchanged. |
| `starling-relay` bin | Keep — now glues storage + http + admin + **embedded Arti** instead of supervising helper processes. |
| `/status` `/manifest` `/events` `/media` endpoints | Keep, unchanged. |
| `/pair` endpoint | Keep, simplified payload (see below). |
| Owner-sig middleware (`X-Starling-Sig`, `X-Starling-Pubkey`) | Keep, unchanged. |
| Zero-knowledge transitive-dep test | Keep, unchanged. |
| `paired_relay` Drift table on phone | Keep — record which relays the phone has paired. |
| `relay_pairing_initiator.dart` on phone | Keep, simplified — no HS-key wrap step. |
| `pending_card_distributions_table.dart` | **Keep** (Plan 15 said delete; R3 needs it for Card-after-pair fanout — already designed for this case). |
| `pushEvents` / `pushMedia` in `lan_network_service.dart` | Keep — phone still pushes encrypted content to its paired relay(s). |
| `relay_paired_owner_table.dart`, `relay_pairing_table.dart`, `served_*_table.dart`, `lib/relay/services/*` on phone | **Delete** (these were for the abandoned phone-as-relay design — Plan 15's deletion list is still correct for these). |
| `Endpoint(type:'relay')` | **Keep** (Plan 15 marked it dead-under-shared-onion; under R3 it's live). |
| `PeerReachabilityMonitor` relay branch | **Keep** (Plan 15 marked it not-needed; under R3 it's used). |

## Pairing flow (revised)

```
Admin opens web UI / runs `starling-relay pair --label "phone-1"`
    │
    ▼
Relay inserts pending_pairings(token=rand(32), expires=now+600, label,
created_by='web'|'cli')
    │
    ▼
Web UI / CLI renders QR encoding starling-relay://pair?card=base64url(CBOR{
    admin_onion_address,
    pairing_token,
    relay_version
})
    │
    ▼ (Owner's phone scans QR OR types token into Settings → Pair a relay)
    │
Phone:
  1. claim = blake2b_256("starling-relay-pair-v1" ||
                        owner_pubkey || admin_onion || pairing_token)
  2. sig = Ed25519.sign(owner_sk, claim)
  3. POST /pair over Tor (CBOR): { owner_pubkey, pairing_token, sig }
    │
    ▼
Relay /pair handler:
  • Look up pending_pairings by token; 409 if consumed_at, 410 if expired
  • Recompute claim; verify sig with ed25519-dalek; 401 on fail
  • Allocate a free loopback port for this Owner's axum instance
  • Generate a fresh HS keypair via Arti's KeyMgr (or
    starling-arti::generate_keypair + launch_onion_service_with_hsid)
  • Call client.launch_onion_service(svc_cfg) with nickname=hex(pubkey),
    wait for the address to publish (~30s typical)
  • INSERT paired_owners(pubkey, label, paired_at,
                          relay_onion_address, local_port, storage_cap_bytes)
  • UPDATE pending_pairings SET consumed_at = now
  • Return 200 CBOR { relay_onion_address, relay_id }
    │
    ▼
Phone:
  • Persist paired_relay(relay_id, paired_at, relay_onion_address)
  • Re-sign Connection Card: existing endpoints + new
    Endpoint(type:'relay', address: relay_onion_address)
  • For each existing Follower: insert pending_card_distributions row
    (target_pubkey, cardCbor, sig, createdAt)
  • Trigger initial backfill: walk own events + media chronologically,
    push via /events, /media to relay_onion_address
  • Mark backfill done
```

`pending_card_distributions` rows drain naturally — next time each
Follower hits the phone's `/manifest`, the updated Card piggybacks
(Plan 13's pattern, already implemented).

## Endpoints (unchanged from Plan 15 §"Endpoints" except for `/pair`)

`/pair` body shrinks to:
```cbor
{
  owner_pubkey: bytes(32),
  pairing_token: bytes(32),
  sig: bytes(64),
}
```

Response:
```cbor
{
  relay_onion_address: text,
  relay_id: bytes(32),  // blake2b_256(relay_onion_address || owner_pubkey)
}
```

## Schema (simplified)

```sql
CREATE TABLE paired_owners (
    pubkey                BLOB PRIMARY KEY NOT NULL,
    label                 TEXT,
    paired_at             INTEGER NOT NULL,
    relay_onion_address   TEXT NOT NULL,
    local_port            INTEGER NOT NULL,
    storage_cap_bytes     INTEGER
);

CREATE TABLE pending_pairings (
    token        BLOB PRIMARY KEY NOT NULL,
    created_at   INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    consumed_at  INTEGER,
    created_by   TEXT NOT NULL,
    label        TEXT
);
CREATE INDEX idx_pending_pairings_expires ON pending_pairings(expires_at);

CREATE TABLE served_events (
    pubkey      BLOB NOT NULL,
    id          TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    msg_seq     INTEGER NOT NULL,
    nonce       BLOB NOT NULL,
    payload     BLOB NOT NULL,
    PRIMARY KEY (pubkey, id),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);
CREATE INDEX idx_served_events_owner_time
    ON served_events(pubkey, created_at DESC);

CREATE TABLE served_media (
    pubkey     BLOB NOT NULL,
    hash       TEXT NOT NULL,
    size       INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    path       TEXT NOT NULL,
    PRIMARY KEY (pubkey, hash),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);

CREATE TABLE admin_credentials (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    password_hash TEXT NOT NULL,
    updated_at    INTEGER NOT NULL
);
```

Unpair = `DELETE FROM paired_owners WHERE pubkey = ?`; CASCADE wipes that
Owner's events + media. The Arti onion service for that nickname is
shut down via `RunningOnionService::drop` (or an explicit
`unpublish` if added — Arti currently unpublishes on drop, which is
sufficient). HS keystore entry for that nickname is removed via
`KeyMgr::remove`.

## What still needs answering under R3

Most of the "smaller design" questions from the earlier list survive
unchanged; a couple change.

1. **Admin onion bootstrap.** First-run, the Rust binary generates an
   HS keypair via Arti for nickname `starling-relay-admin`, launches it,
   captures the address, prints to logs + writes to
   `${data_dir}/admin_onion.txt`. The admin web UI templates use it.
   Concrete, not blocking.

2. **Loopback port allocation.** Range `17000–17999`. At pair time the
   relay picks the lowest unused port in that range (query
   `paired_owners.local_port`), inserts. On restart, each Owner's axum
   instance binds to its stored port.

3. **Admin Unix-socket protocol.** Single endpoint: `POST /pair-token`
   with optional `{label}` body, returns `{token, admin_onion_address,
   expires_at}`. JSON, line-delimited. Socket mode `0600`, parent dir
   `0700`. CLI is a 30-line client.

4. **SQLite concurrency.** Single `r2d2::Pool<SqliteConnectionManager>`
   instantiated at startup, shared across all per-Owner axum instances
   and the admin UI. `PRAGMA journal_mode=WAL`, `PRAGMA synchronous=NORMAL`,
   `PRAGMA busy_timeout=5000`. Standard.

5. **Storage cap pruning.** When an Owner's `served_events`/`served_media`
   bytes exceed their cap, `POST /events` and `POST /media` return 507.
   Pruning is **manual via the admin UI** for v1 — the admin clicks
   "Reclaim space" on the Owner row, which deletes oldest first up to
   N% of the cap. Auto-pruning is v2. Out-of-app pruning means the
   phone's view of "what the relay still has" can be stale; the phone
   re-pushes any event the relay 404s on. Idempotent inserts make this
   safe.

6. **PairingClaim wire-vector.** Lives in `starling-wire/test_vectors/`
   only (relay-specific endpoint). Dart-side fixture in
   `test/services/relay_pairing_initiator_claim_test.dart` reads the
   same vector. Not in `protocol/plans/protocol-spec.md`.

7. **Multi-endpoint selection on the Follower side.** ~~Race all onion
   endpoints, or track per-endpoint state?~~ **Resolved.** Not a race —
   `PeerReachabilityMonitor._priority` is a strict ladder. The phone's
   own onion (`type == 'onion'`) and the relay's onion
   (`type == 'relay'`) are distinct transport tiers, with the relay
   ranked last so a reachable phone↔phone path always wins. Selection
   runs only over already-probed-reachable transports, so ranking the
   phone onion above the relay never stalls on an asleep phone.

8. **First-pair publication latency.** ~30s for Arti to publish the new
   onion's descriptor. The pairing handler can wait synchronously by
   polling `RunningOnionService::status()` until reachable, then return.
   Alternative: return immediately and let the phone re-test reachability.
   Sync wait is simpler UX-wise; do that with a 60s timeout, 504 on
   timeout (rare).

## Action items for plan 15 doc

1. Apply this decision back into `15-desktop-relay.md` (or supersede it
   with `15-headless-relay.md` per the rename note at the top of plan
   15). This is a structural rewrite — probably worth doing in one
   pass once R3 is locked in.
2. Update §"Risks / open questions" — strike OnionBalance interop and
   per-Owner Tor circuit cost lines.
3. Update §"Critical files" — replace `import_hs_key()` / `export_hs_key()`
   helper references with the multi-launch-onion-service usage of
   `starling-arti`.
4. Reflect the simplified `/pair` claim in the Dart-side spec amendment
   row 6.
