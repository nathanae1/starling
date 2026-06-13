# Plan 15 review findings — headless relay

Code review of commits `4413b8b` (`.15`) and `3f75152` (`.15 phone`), covering the
new Rust relay workspace (`relay/`), deletion of the old in-app Dart relay, the
shared `starling-arti` crate, and phone-side relay integration.

Verification status: `CONFIRMED` = trigger + wrong output named and reproduced
from code; `PLAUSIBLE` = mechanism proven, trigger depends on timing/env/config;
`FIXED` = addressed in the working tree — see the **Fixed:** note under the
finding for what was done and how it was verified.
Wire-format interop (Dart↔Rust CBOR + pairing-claim signature bytes) was checked
field-by-field and is **clean** — and is now pinned by cross-language test
vectors (see Cleanup/altitude), so it stays that way.

---

## Blockers (ship-stoppers)

All four blockers fixed 2026-06-10 (working tree, not yet committed).

### B1. Phone bridge does not compile — `FIXED`
`app/starling/native/starling_bridge/src/arti/mod.rs:236`
`guard.create_onion_service(local_port).await` awaits a fn the extraction to
`starling-arti` made synchronous (returns `Result<String>`). `cargo check` fails
E0277; every iOS/Android build that compiles the native bridge is broken.
**Fix:** drop the stray `.await`.
**Fixed:** `.await` removed; the `block_on` wrapper stays (the sync fn still
`tokio::spawn`s internally and needs the runtime context). Bridge `cargo check`
passes.

### B2. Relay tier can never sync — `FIXED`
`app/starling/lib/sync/transport_router.dart:49`
`PeerTransport.relay` falls through to `_lan` (plain `http.Client`), but relay
endpoints are `.onion` (reachable only via Tor SOCKS). `PeerReachabilityMonitor`
probes relay *over Tor* and marks it reachable, so sync resolves a relay
`PeerConnection` → LAN client → `SocketException` on the `.onion` host →
mark-unreachable → re-probe reachable. Permanent flap; the follower-fetches-from-
relay path (the point of Plan 15) never runs.
**Fix:** route `PeerTransport.relay` to `_tor` (mirror the monitor's
`useTor: transport == tor || transport == relay` predicate; ideally derive
dialer from the endpoint address class so the two sites can't drift).
**Fixed:** router now sends relay → `_tor`; new `PeerTransportDialing.dialsViaTor`
extension (`types.dart`) is the shared predicate, used by both
`peer_reachability_monitor` probe sites. New `test/sync/transport_router_test.dart`
pins per-transport routing + the predicate (6 tests). ⚠ Fixing this arms D9 —
see below.

### B3. Relay fails Tor bootstrap on standard hosts — `FIXED`
`relay/crates/starling-arti/src/lib.rs:84-90`
`create_dir_all` makes `state/` + `cache/` at 0755 under umask 022; the relay
passes strict fs-mistrust, which rejects group/other-readable state dirs
(reproduced: *"Incorrect permissions … must be g-rx,o-rx"*). Every
systemd/Docker/Debian deploy crashes at first `serve`. Phone path passes
`trust_permissions=true`, so it's unaffected.
**Fix:** create these dirs with mode 0700 (`DirBuilder::mode`), or only create the
parent and let Arti make its own dirs.
**Fixed:** new `ensure_private_dir` in `starling-arti` creates `data_dir`/`cache`/
`state` with mode 0700 *and* chmods 0700 after, healing dirs a pre-fix run left
at 0755; creation errors now propagate (old `.ok()`s dropped). Unit-tested
(fresh-create + heal-existing).

### B4. Docker image crash-loops — `FIXED`
`relay/docker/Dockerfile:38-44`
`distroless:nonroot` (uid 65532) + `VOLUME /var/lib/starling-relay` with no
`mkdir`/`chown` → mountpoint is root:root 0755 → `create_dir_all(media_dir)`
returns EACCES (propagated from `main.rs`) before Arti is reached. The documented
Docker path never boots. (systemd path is fine — it uses
`StateDirectory`/`StateDirectoryMode=0700`.)
**Fix:** create + chown the data dir in the image, or run as a uid that owns the
volume.
**Fixed:** Dockerfile `COPY --from=builder --chown=65532:65532`s an empty dir onto
`/var/lib/starling-relay` *before* the `VOLUME` instruction (named volumes inherit
the ownership); README notes bind mounts need `chown -R 65532:65532` on the host.
Not yet validated with a real `docker build` (no daemon on the dev box) — smoke
test: `docker run --rm -v vol:/var/lib/starling-relay starling-relay migrate`.

---

## Security & privacy

All seven fixed 2026-06-10 (working tree, not yet committed).

### S1. Cross-owner media corruption — `FIXED`
`relay/crates/starling-relay-http/src/routes/media.rs:17,69-100`
Blobs are stored at a hash-only shared path (no per-owner namespace) and the body
is never verified to hash to the URL `<hash>`; the idempotency check is a
per-owner DB row. A validly-paired Owner B can `POST /media/<A's hash>` with
arbitrary bytes → `media::get(B,H)`=None → `fs::write` clobbers A's file. A's
followers get undecryptable data; A can't heal (A's row still exists → 202 without
rewrite).
**Fix:** namespace the path per owner pubkey, and/or verify the body hashes to the
URL hash before writing.
**Fixed:** new `owner_shard_path` writes blobs at `media_dir/<owner_hex>/<shard>`
(hash-verify is impossible by design — blobs are ciphertext keyed by the
*plaintext* hash, see `media_service.dart:66-71`). GET is unchanged (reads the
per-owner DB row's `path`). New `cross_owner_media_cannot_clobber` test pins it.
Side benefit: D4's unpair cleanup can later be a `remove_dir_all` of the owner
dir.

### S2. Connection-card replay pins endpoints forever — `FIXED`
`app/starling/lib/sync/sync_engine.dart:415-431`
The Ed25519 sig covers `card_cbor` only (no timestamp inside); the monotonic
drop-gate trusts the *unsigned* `delivery.createdAt`. A LAN MITM serving
`/manifest` replays any previously-signed card with `created_at=MAX` → sig passes
→ `lastReceivedCardAt` jumps to MAX → all future legitimate card updates dropped.
The feed-key path binds its timestamp inside signed bytes; the card path diverged.
**Fix:** put `created_at` (or a monotonic counter) *inside* the signed card bytes
and gate on that.
**Fixed:** (with S3b) card deliveries are now sealed exactly like `new_feed_key`:
XChaCha20-Poly1305 under the X25519 DH shared key with `createdAt` bound into
`deriveSharedKey` — a replayed delivery with an inflated `created_at` changes the
derived key and fails AEAD decrypt, so the monotonic gate can't be poisoned. The
detached Ed25519 sig was dropped (the DH AEAD authenticates the owner; only the
two parties can compute the key — matches the feed-key pattern). Schema:
`pending_card_distributions` rows are `{encryptedCard, nonce}` (drift v6, drop +
recreate — transient outbox). Replay test pins `lastReceivedCardAt` staying put.

### S3. Unauthenticated card ack-spoof + cleartext card disclosure — `FIXED`
`app/starling/lib/server/handlers/manifest_handler.dart:100-105,137-144`
`card_seen_at` is honored for any self-asserted `requester_pubkey` (no auth) —
`GET /manifest?requester_pubkey=<victim>&card_seen_at=MAX` permanently suppresses
the victim's pending card. Separately, `new_connection_card` is signed but **not**
sealed to the follower (unlike `new_feed_key`), so anyone asserting a follower
pubkey is handed the owner's new relay onion in cleartext. (Ack-spoof pattern is
pre-existing for `ack_rotation_at`; this change extends it to cards.)
**Fix:** require a possession proof for acks, and/or seal the card to the
follower's key as `new_feed_key` does.
**Fixed:** both halves. (a) Acks now require an `ack_sig` possession proof
(`sync/manifest_ack.dart`): Ed25519 over
`blake2b256("starling-manifest-ack-v1" || owner_pk || u64be(ack_rotation_at) ||
u64be(card_seen_at))` — covers the **pre-existing** `ack_rotation_at` spoof too.
Verified at the shared `buildManifestResponseBytes` chokepoint (HTTP + libp2p);
missing/invalid sig → acks silently ignored, manifest still served. Same-owner
replay is harmless (mark-delivered is monotonic); cross-owner replay is blocked
by the owner-pubkey binding. (b) Cards are sealed per follower — see S2. Note
sealing alone doesn't help against a *removed* follower (they hold valid keys);
that's S4.

### S4. Removed follower still receives the fresh card — `FIXED`
`app/starling/lib/services/storage_service.dart` +
`app/starling/lib/services/storage/daos/paired_relay_dao.dart:70-79`
`clearCardDistributionsFor` is implemented 3× but has **zero call sites**;
`removeFollower` never clears pending card rows, and `latestPendingCardFor` has no
followers-table join. A removed follower (still polling `/manifest`, or anyone
replaying their pubkey) is served the owner's new relay onion — the exact leak the
method exists to prevent.
**Fix:** call `clearCardDistributionsFor` on follower removal (next to the
existing `clearPendingDistributionsFor` call in `key_rotation_service`), and/or
join the followers table in `latestPendingCardFor`.
**Fixed:** `FollowService.removeFollower` now calls `clearCardDistributionsFor`
unconditionally (before the null-guarded rotation; `unfollow` routes through it —
single chokepoint). Defense in depth: `buildManifestResponseBytes` attaches
`new_feed_key`/`new_connection_card` only when
`storage.isAcceptedFollower(requesterPubkey)` — covers rows queued after a
removal raced in. Tests in `follow_service_test` + `manifest_handler_test`.

### S5. Pairing token is not single-use — `FIXED`
`relay/crates/starling-relay-admin/src/lib.rs:445-465,90-102`
`pair_post` checks `consumed_at`, then awaits the ~30s onion launch, *then* calls
`mark_consumed` ignoring its rows-affected result → concurrent claims with one
token both pair. Minting a new token no longer invalidates the prior one (old
Dart relay kept exactly one active token), and the `/pair` page meta-refreshes
every 120s, so a photographed QR stays claimable for the full ~10min TTL.
**Fix:** make `mark_consumed` the atomic claim (`UPDATE … WHERE consumed_at IS
NULL`, require `rows==1`) *before* the launch; invalidate prior tokens on mint.
**Fixed:** `pair_post` reordered — claim sig verified first, then
`mark_consumed` is the atomic claim (rows==1 required, else 409) *before* the
launch; the post-launch consume is gone. New `pairings::consume_all_unconsumed`
runs on every mint, restoring exactly-one-active-token (the auto-refreshing
`/pair` page makes the displayed QR the only valid one). An already-paired owner
retrying (phone 30s timeout) skips the token entirely — the verified sig +
supervisor's idempotent re-pair branch return the live onion. A failed launch
burns the token (operator re-mints). New `tests/pair_post.rs` pins: concurrent
same-token claims → one 200 + one 409 mid-launch; mint invalidates prior;
already-paired retry → 200; bad sig doesn't burn the token.

### S6. CSRF on destructive unpair + insecure container default — `FIXED`
`relay/crates/starling-relay-admin/src/lib.rs:134,407-418` +
`relay/docker/Dockerfile:42-43`
`POST /api/unpair/:pubkey` has no CSRF token / Origin / content-type guard (a
"simple request"). The Dockerfile sets `STARLING_RELAY_BIND_ADMIN=0.0.0.0:8088`
with no password, and `basic_auth_mw` passes through when no creds row exists, so
a drive-by page can mint pairing tokens and unpair owners (pubkey derivable from
any follower's card). With a password set, browsers auto-replay cached Basic creds
cross-site.
**Fix:** add Origin/CSRF-token checks to mutating admin routes; keep the default
admin bind on localhost (don't override to 0.0.0.0 in the image).
**Fixed:** `api_unpair` requires the `X-Starling-Csrf` custom header (forces a
CORS preflight the server never answers — kills simple-request CSRF) and rejects
`Sec-Fetch-Site: cross-site`; the dashboard fetch sends the header. `GET /pair`
(state-changing since S5 invalidate-on-mint) rejects cross-site too. Dockerfile
no longer overrides the admin bind — in-container default is loopback; README
documents the explicit opt-in (`set-password` first, then
`-e STARLING_RELAY_BIND_ADMIN=0.0.0.0:8088 -p 127.0.0.1:8088:8088`). `serve`
logs a prominent warning when admin is bound non-loopback with no password
(warn-not-refuse, per user decision — trusted-LAN/Tailscale setups stay viable).
CSRF tests in `tests/pair_post.rs`.

### S7. Follower identity leaked to the relay — `FIXED`
`app/starling/lib/services/lan_network_service.dart:74`
`fetchManifest` unconditionally appends `requester_pubkey` (+ `ack_rotation_at` /
`card_seen_at`) for all transports; nothing strips them for relay connections. The
relay ignores the param but the operator/logs now see each follower's pubkey +
poll cadence — directly against the new comment *"avoids leaking Follower access
patterns to the always-on box"* and the zero-knowledge positioning. Followers
never pair, so this is genuinely new info to the relay.
**Fix:** strip `requester_pubkey`/ack params for `PeerTransport.relay` requests.
**Fixed:** all identity params (`requester_pubkey`, `ack_rotation_at`,
`card_seen_at`, and S3a's new `ack_sig`) are gated behind
`connection.transport != PeerTransport.relay` in `LanNetworkService.fetchManifest`
(the instance relay connections route through) and mirrored in
`Libp2pNetworkService` as drift insurance. Other fetch paths verified clean
(`/events` carries only `since`; `/media` is path-only; reachability probes hit
`/status` with no params). New `lan_network_service_test.dart` pins relay →
`{since}` only, lan/tor → full params.

---

## Data loss & availability

All nine fixed 2026-06-11 (working tree, not yet committed).

### D1. Late relay events permanently missed — `FIXED`
`app/starling/lib/sync/sync_engine.dart:240,306`
Manifests filter on the *author's* `created_at`, but the follower advances
`lastSyncedAt` to wall-clock now on every exchange (incl. upToDate). An event that
reaches the relay after the window passed its author time (routine: `pushPublished`
fails, a later `reconcile` heals it) is `created_at >= since`-false in every future
manifest — on the relay *and* on later direct phone sync → silent post loss.
**Fix:** page/sync by a monotonic server-receipt cursor, or don't advance the
since-cursor past events that haven't been confirmed present.
**Fixed:** (user decision: created_at cursor + periodic full diff, not a
receipt-seq protocol change.) The cursor now advances only to the max author
`created_at` observed in the manifest — never wall-clock — clamped to
`now + 300s` against skewed-clock events; an empty window doesn't advance.
Out-of-order arrivals (the residual hole) are caught by a periodic FULL paged
manifest diff per follow (new `fetchAndDiffFull` + `sync/manifest_pager.dart`):
runs on first sync, every 24h (`follows.lastFullSyncAt`, drift v6→v7
`addColumn`), and whenever a windowed manifest reports `has_older`. Tests pin
cursor == max created_at (not wall clock), the clamp, no-advance-on-empty,
windowed-miss → full-pass recovery, and the `has_older` redo.

### D2. Backfill stranded "syncing…" forever — `FIXED`
`app/starling/lib/services/relay_push_coordinator.dart:74-86`
Entire history is pushed as one unchunked `POST /events`; the axum router sets no
`DefaultBodyLimit`, so bodies >2 MB get 413. `_withRelay` swallows it,
`markRelayBackfillComplete` runs only after full success and only from the
one-shot unawaited `backfill()` — so *any* transient failure strands
`backfillComplete=false` (UI "syncing…" forever), and `reconcile` 413s the same
way.
**Fix:** chunk pushes into bounded batches; raise the relay body limit to a sane
cap (old relay used 4 MiB); make `reconcile` able to set `backfillComplete` once
the relay has converged.
**Fixed:** pushes are chunked (100 items or 1 MiB per batch, whichever first);
the relay's owner router sets `DefaultBodyLimit` 4 MiB (3 MiB-accepted and
>4 MiB-413 pinned by tests). `backfill()`/`reconcile()` collapsed onto one
`_syncToRelay` diff pass — either sets `backfillComplete` once events AND
media (D8) have both converged, so one transport flap no longer strands
"syncing…" forever. Pinned by the new `relay_push_coordinator_test.dart`.

### D3. Pair race leaves an owner unserved — `FIXED`
`relay/crates/starling-relay/src/supervisor.rs:137-177`
The already-paired check runs *before* `pair_lock`; two concurrent pairs for one
pubkey both proceed, the second `launch_owner` overwrites the owners-map entry
(dropping the live `OwnerTask` → onion unpublished), then its `owners::insert`
hits the PK conflict → `stop_owner` tears down the replacement → a `paired_owners`
row with nothing serving until restart. Triggered by the phone's 30s pair timeout
+ retry. Related: the re-pair branch returns the persisted onion without checking
a live task, so after a failed `restore_all` a re-pair returns 200 for a dead
endpoint.
**Fix:** take `pair_lock` before the already-paired check; on re-pair, verify (and
relaunch) the live task instead of trusting the DB row.
**Fixed:** `pair_lock` is now taken at the top of `pair_owner` (and
`unpair_owner` — serializing unpair against a concurrent re-pair); holding it
across the ~30s launch is intentional. The re-pair branch checks the owners
map for a live task and relaunches on the persisted `local_port` when absent
(same keystore nickname → same onion address), healing the
dead-endpoint-after-failed-restore case. Lock order documented as
`pair_lock → owners`, never reversed. Idempotent-re-pair contract stays pinned
by `pair_post.rs`; the race itself is structural (check now inside the lock).

### D4. Storage caps don't hold; unpair leaks data — `FIXED`
`relay/crates/starling-relay/src/supervisor.rs:189-199` +
`relay/crates/starling-relay-http/src/routes/media.rs:76`
`unpair_owner` deletes only DB rows — media blob files are never removed from disk
(leak; admin UI promises "delete all stored data"). `Caps.disk_cap` (config +
env-plumbed) is **never read** (the "enforced at supervisor level" comment is
false), and `POST /events` has no size accounting — host storage is unbounded and
can fill the disk, taking down SQLite + Tor.
**Fix:** delete blob files on unpair (with refcounting if S1's shared-path design
stays); enforce `disk_cap` and an events size cap at one accounting chokepoint.
**Fixed:** `unpair_owner` now `remove_dir_all`s the S1 per-owner blob dir (no
refcounting needed — S1 namespaced the paths). New
`starling-relay-storage/src/accounting.rs` chokepoint: per-owner cap covers
events + media **combined** (vs `storage_cap_bytes` else `per_owner_default`),
host-wide `disk_cap` sums both tables across owners; both `POST /events` and
`POST /media` call it and 507 with distinct messages. `served_events` gained a
`size` column (migration `0002_event_size.sql`; `Db::migrate` now gates on
`PRAGMA user_version`). The events insert loop also runs in one transaction
(folds the Efficiency finding). Tests: owner-cap 507 via events, media push
counting stored event bytes, host cap spanning two owners.

### D5. Relay stalls under load (blocking SQLite on tokio) — `FIXED`
`relay/crates/starling-relay-http/src/routes/{events,manifest,media,status}.rs`
Every handler runs rusqlite + r2d2 checkout (30s) directly on tokio workers (no
`spawn_blocking`); media push holds the conn across `fs` awaits. On 1–2 core
boxes a backfill + concurrent reads parks all workers → whole relay (all onions +
admin) stalls.
**Fix:** wrap blocking DB/fs work in `spawn_blocking`, or use an async pool.
**Fixed:** new `Db::run` (pool checkout + closure on `spawn_blocking`; doc
rule: never call holding a `PooledConn` — the in-memory test pool is size 1).
All owner routes (`events`, `manifest`, `media`, `status`) and the admin hot
paths (`basic_auth_mw` creds lookup, `pair_post` token claim, `api_owners`,
`pair_page`, `health`, `admin_sock`) refactored onto it; `mint_pairing_token`
now takes `&Connection`. Media push does its fs writes via `std::fs` inside
the same blocking closure — no connection held across awaits. argon2 verify
also moved to `spawn_blocking` (the inline-argon2 Efficiency finding's CPU
half). Behavior-preserving; pinned by the existing suites staying green.

### D6. No rate limiting anywhere — `FIXED`
`relay/crates/starling-relay-http`, `relay/crates/starling-relay-admin`
The old Dart relay had 360/min + 429; the new relay has none on owner routers,
`/pair`, or admin. `GET /events` buffers up to 500 full payloads per request — one
Tor client can peg the always-on box.
**Fix:** add a tower rate-limit layer (per-route) returning 429 + Retry-After.
**Fixed:** in-house token bucket (`starling-relay-http/src/rate_limit.rs`, no
new deps; client identity is meaningless behind onions, so the bucket is
per-router = per owner endpoint / per admin surface). Owner routers 360/min
burst 60 (old Dart relay parity); admin UI 120/min burst 30 (layered OUTSIDE
basic-auth so it fires before argon2 burns CPU); `/pair` 10/min burst 5.
429 + `Retry-After`. Tests at bucket, owner-router, and pair-router level.
The admin crate gained a dep on `starling-relay-http` for the shared
middleware (no cycle).

### D7. >1000-event history re-pushed every sync — `FIXED`
`app/starling/lib/services/relay_push_coordinator.dart:186`
`_relayEventIds` reads only the first `/manifest` page (relay `PAGE_LIMIT=1000`,
`has_older` ignored). Owners with >1000 events re-push the older events **and their
media bytes over Tor on every sync pass, forever** (relay dedups, so it's wasted
bandwidth/battery).
**Fix:** page the manifest (`until`/`has_older`) or track a reconciled-through
cursor.
**Fixed:** `_relayEventIds` pages `/manifest` to completion (50-page runaway
cap; a partial set degrades to idempotent re-push). Paging safely required
fixing the latent same-second tiebreaker bug (see "Smaller correctness"):
both servers now order `(created_at DESC, id DESC)` and accept an `until_id`
keyset cursor (bare `until` keeps the old inclusive semantics; clients page
with `until = oldest.created_at, until_id = oldest.id` — no `-1`). Reconcile
also diffs ids BEFORE loading payloads, killing the N+1 decode (Efficiency
finding folded). Pinned on both servers (storage + router walk tests, Dart
manifest_handler keyset test) and in `relay_push_coordinator_test.dart`.

### D8. Media never re-checked → permanent 404 — `FIXED`
`app/starling/lib/services/relay_push_coordinator.dart:95-115`
`reconcile` diffs event ids only, never media presence; `_pushMediaFor` aborts on
the first throw and `_withRelay` swallows it → a media upload that fails after its
event was accepted is never retried → permanent 404 for followers fetching that
media via the relay.
**Fix:** diff media presence too (HEAD/media-manifest), and don't abort the whole
batch on one media failure.
**Fixed:** new relay endpoint `GET /media-manifest?after=<hash>` (owner-signed
over the empty body; CBOR `{hashes, has_older}`, `hash ASC` keyset paging —
one round trip per 1000 blobs instead of N HEADs over Tor; the hashes already
key the relay's blobs, so zero-knowledge posture is unchanged). Reconcile now
diffs media presence and re-pushes the gap; `_pushMediaFor` was replaced by
`_pushMediaHashes` with per-blob try/catch (one bad upload no longer strands
the rest), and any media failure keeps `backfillComplete` unset until a later
pass heals it (ties into D2). Blobs no longer on disk are skipped — they can
never heal, so they don't block convergence. Tests: endpoint auth + paging
(Rust), presence-diff / per-blob-tolerance / heal-then-converge (Dart).

### D9. Outbound queue deleted into a relay 401 — `FIXED`
`app/starling/lib/sync/outbound_drain.dart:57` + `sync_engine.dart:313`
Sync drains the follower's outbound queue into relay `POST /events` (owner-sig
required → 401; also `Envelope` vs `PushBatch` shape mismatch) and deletes the
queued comments/likes after 3 retries (no transport-vs-4xx distinction). Was
blocked by B2; **B2 is now fixed, so this is live** — relay-reachable follows
with queued outbound items will start dropping them. Fix before shipping the
B2 fix.
**Fix:** don't drain outbound to a relay connection; and don't count HTTP 4xx the
same as transient transport errors toward the drop threshold.
**Fixed:** both halves, landing WITH B2 as required. (a) `SyncEngine` routes
both drain call sites through `_drainOutbound`, which no-ops on
`PeerTransport.relay` — queued comments/likes wait for a direct tier. (b)
`NetworkException` now carries `statusCode`; the drain's retry policy drops
only after 3 HTTP-4xx *rejections* — transport-level failures and 5xx retry
forever without touching `retry_count` (three Tor flaps no longer delete a
comment). Tests: relay-transport sync leaves the queue intact +
`pushEnvelope` uncalled; transport errors never increment across many passes;
401×3 drops; 500 counts as transient.

---

## Smaller correctness / UX

All five fixed 2026-06-11 (working tree, not yet committed); the events.rs
item had already landed with D7.

- **`relay_pairing_service.dart:80`** (`FIXED`) — `unpair()` clears the
  paired-relay row first, then silently skips card redistribution if
  identity/keychain lookup returns null (no error, no retry) → followers keep
  using the unpaired relay. **Fixed:** lookups hoisted above the mutation;
  null identity now throws `StateError` before anything changes (mirrors
  `pair()`), so it's full-unpair-or-nothing. The settings screen catches and
  shows a "Couldn't unpair" snackbar. Test pins row-intact + no card queued
  on null identity (`relay_pairing_service_test.dart`).
- **`connection_settings_screen.dart:221`** (`FIXED`) — `_unpair` calls
  `setState`/`ref.read` after awaiting the confirm sheet with no `mounted` check
  → "setState after dispose" if the screen is torn down while the sheet is up.
  **Fixed:** `if (confirmed != true || !mounted) return;` (repo-standard
  early-return guard).
- **`post_provider.dart:25`** (`FIXED`) — `onPublished` reads an autoDispose
  `ref` after an async gap, fired unawaited with no catch → `UnmountedRefException`
  on publish (relay mirror deferred to next reconcile). **Fixed:** the
  coordinator future (keepAlive) is captured at provider build via
  `ref.watch(...future)` — the unawaited callback never touches `ref` — and the
  body is try/caught best-effort (next reconcile heals), matching
  `sync_provider`'s `_reconcileRelay`. Side benefit: the mirror now still runs
  when the compose screen pops immediately, instead of deferring.
- **`relay_pairing_initiator.dart:26`** (`FIXED`) — phone `/pair` POST timeout
  (30s) == relay's ~30s onion launch (before Tor RTT) → routine client timeout
  while the relay completes; re-scanning the same QR shows raw
  `409 "token already used"`. Widen the timeout / surface a friendlier message.
  **Fixed:** default timeout 30s → 90s; the confirm sheet maps 409 → "already
  claimed — relay may still be finishing, try again in a minute" (retry with
  the same claim is idempotent once the launch lands, per S5) and
  `TimeoutException` → "relay didn't respond in time", plus a "this can take a
  minute" hint while pairing. New widget tests
  (`confirm_relay_pairing_sheet_test.dart`) pin both messages through the real
  initiator over a mock transport.
- **`relay/crates/starling-relay-storage/src/events.rs:56-61`** (`FIXED`,
  with D7) — `manifest_page` orders `created_at DESC` with no id tiebreaker;
  same-second events truncated by `LIMIT` are skipped by the documented
  `until = oldest.created_at - 1` paging. Broken relay contract once any client
  pages. **Fixed:** keyset pagination `(created_at DESC, id DESC)` + `until_id`
  on both servers — see D7's note.

## Efficiency

Both open items fixed 2026-06-12 (working tree, not yet committed).

- **`admin/src/lib.rs:190`** (`FIXED`) — `basic_auth_mw` runs argon2id (~19 MiB, t=2)
  inline per request on the runtime; the `/pair` page polls `/api/owners` every 3s → a
  left-open tab steals real CPU on a Pi-class box. Use a session cookie +
  `spawn_blocking` for argon2.
  **Fixed:** (user decision: in-memory verified-password cache, not a session
  cookie.) `AdminState.auth_cache` holds `(PHC string, blake2b256(password))` of
  the last successful argon2 verify; later requests do a constant-time digest
  compare (`subtle`) and skip argon2 when the entry is keyed to the *current*
  stored PHC — `set-password` rotates the PHC, invalidating it naturally.
  Basic-auth UX and the S6 CSRF posture are unchanged. Tests
  (`tests/pair_post.rs`): mw 401/200 matrix with creds set, and a
  cache-proof test (pre-seeded cache entry authenticates a password argon2
  would *reject* — proving the fast path; cold cache → 401; stale-PHC entry
  ignored).
- **`routes/media.rs:41`** (`FIXED`) — `GET /media` reads the whole blob into RAM (no
  streaming, no per-blob bound). Stream with `ReaderStream`.
  **Fixed:** handler streams `tokio::fs::File` via `tokio_util::io::ReaderStream`
  → `Body::from_stream`, with `Content-Length` set from file metadata
  (open/metadata errors → 404 as before). Existing
  `media_push_get_and_validation` pins the response bytes unchanged.
- **`relay_push_coordinator.dart:99,177`** (`FIXED`, with D7) — `reconcile`
  loads + CBOR-decodes **all** own payloads (N+1 `getEncryptedPayload`) before
  diffing even when nothing's missing; the decode exists only to re-encode in
  `pushEvents`. **Fixed:** ids diff first; payloads load only for missing ids.
- **`routes/events.rs:63`** (`FIXED`, with D4) — each batch item inserts in its
  own autocommit; **fixed:** the push loop runs in one transaction.

## Config / ops

Both fixed 2026-06-12 (working tree, not yet committed).

- **`relay/crates/starling-relay/src/config.rs:50`** (`FIXED`) — `apply_env()`
  handles every field *except* `local_port_range`, contradicting
  config.example.toml's "every value overridable via env" (Docker is env-only).
  **Fixed:** `STARLING_RELAY_LOCAL_PORT_RANGE=17000-17999` wired via a pure
  `parse_port_range` (trim, `-`-split, both u16, `start <= end`; malformed →
  ignored like the other fields). Parser unit-tested; format documented in
  config.example.toml.
- **`relay/scripts/install-debian.sh`** (`FIXED`) — header claims
  idempotent/upgrade-safe but never `systemctl restart`; a re-run installs the new
  binary while the old one keeps running.
  **Fixed:** `systemctl enable --now` → `systemctl enable` + `systemctl restart`
  (restart starts a stopped unit, so fresh install still works; upgrade now
  actually swaps onto the new binary).

## Cleanup / altitude (quality, no crash)

All items resolved 2026-06-12 (working tree, not yet committed) — fixed except
the base32 swap, which is a recorded won't-fix.

- Hand-rolled Crockford base32 (`starling-wire/src/base32.rs`) and hex
  (`admin/src/lib.rs`) duplicate `data-encoding` / `hex` already in the tree.
  **Fixed (hex):** admin's `hex_encode`/`decode_hex32` now use the `hex` crate.
  **Won't-fix (base32):** the module is a deliberate byte-for-byte port of
  `services/crypto/crockford_base32.dart` including the Crockford look-alike
  normalization (i,l→1, o→0); `data-encoding` would need a custom
  `Specification` of similar size on a wire-critical codec for zero functional
  gain. The new wire vectors pin the two implementations against each other
  instead.
- `_loadSecretKey` is a 6th copy of the keychain-read helper; the manifest-parse
  block is duplicated across LAN/libp2p services; `now_secs` defined 5×,
  `internal()` 2×, `_baseUrl` onion idiom 4×, `Caps::default` constants duplicate
  `config.rs`.
  **Fixed:** secret-key reads → `KeychainManager.loadIdentitySecretKey()` (5
  copies removed: main, follow/sync/relay providers, background_sync_runner);
  manifest parsing → `sync/manifest_codec.dart#parseManifestResponse` (both
  services); `now_secs` (real count 3×, all Rust) → `starling_wire::now_secs`;
  `internal()` → exported from `starling-relay-http`, admin reuses it; the
  `http://$addr` ternary ×4 → `httpBaseUrlForAddress` in `types.dart`
  (follow_service's variant kept — different semantics: `:80` only for onion
  type); `Config::default()` now derives the cap defaults from
  `Caps::default()`.
- Dead code: `ownerSignatureMiddleware` (zero callers after the in-app relay
  deletion); the supervisor's graceful-shutdown machinery (defeated by an
  immediate `abort()`); `ArtiNode::client()`/`nickname()` + unused
  `tor-keymgr`/`fs-mistrust` deps.
  **Fixed:** middleware file deleted; supervisor's oneshot +
  `with_graceful_shutdown` removed (abort-only, documented — the onions die
  with the process, so a drain buys nothing); `ArtiNode::client()` removed
  (re-add when the M5 keystore-erasure spike lands) and `OnionHandle::nickname()`
  + its now-unread field removed; `tor-keymgr`/`fs-mistrust` dropped from
  starling-arti and the workspace deps (relay + bridge `cargo check`/`test`
  green — they weren't load-bearing for feature unification).
- Altitude: **no cross-language wire test vectors** pinning the Dart↔Rust CBOR/sig
  formats (correct today, but nothing prevents drift); connection-card delivery is
  a structural clone of key-rotation delivery (~10-file pattern repeated);
  phone-only state (`onion` slot, fake `circuit_count=3`) pushed into the shared
  `starling-arti` crate instead of composed at the phone edge.
  **Fixed (all three, user decision to include the unification):**
  - *Wire vectors:* `test/vectors/index.json` gained a `relay_wire` section
    (generated by `vectors_gen.dart`) covering every Dart↔Rust surface:
    Crockford base32, pairing claim digest+sig+CBOR, `relay_id`+`PairResponse`,
    `RelayQrCard`, `EncryptedEvent` blob, `PushBatch`+owner-sig, `PushReceipt`,
    manifest + media-manifest pages, and the `/events` Envelope. Dart asserts in
    `vectors_test.dart`; new `relay/crates/starling-wire/tests/wire_vectors.rs`
    decodes Dart-produced bytes and asserts Rust-produced surfaces
    byte-for-byte (Dart `cbor` and Rust `ciborium` proved byte-identical).
    The manifest-ack sig is pinned Dart-side only (it never crosses to Rust).
  - *Delivery unification:* new `lib/sync/sealed_delivery.dart` single-homes
    the construction (seal/unseal with createdAt-bound DH), the owner queue
    loop, the manifest attach (S4 acceptance gate INSIDE), the ack-mark (S3a
    proof inside), clear-on-removal (iterates the channel registry), and
    transport-side parsing. `RotatedFeedKeyDelivery`/`ConnectionCardDelivery`
    collapsed into `SealedDelivery`; KeyRotationService lost its
    `ContentKeyService` dep; storage tables/DAOs and `manifest_ack.dart`
    intentionally untouched (the ack digest is two-slot by design — a third
    kind needs `…-ack-v2`). `manifest_handler_test` passed with **zero edits**
    (pure code motion); new `sealed_delivery_test.dart` pins the construction
    against the literal pre-refactor derivation in both directions. Semantic
    delta (intentional, strict tightening): `removeFollower` now clears
    pending *feed-key* rows too, even when no rotator is wired.
  - *Phone-state extraction:* the `onion` slot, `create_onion_service`, and
    `PHONE_HS_NICKNAME` moved to the bridge's `arti/mod.rs` (handle owns its
    own `Mutex<Option<OnionHandle>>`; idempotent-reattach and serialization
    semantics preserved); `StatusSnapshot` lost the fake `circuit_count` —
    the bridge fabricates `ready ? 3 : 0` at the FFI edge where the
    Dart-pinned struct needs it; `ArtiNode::shutdown` reduces to SOCKS
    teardown (onion handles are caller-owned).

## Follow-ups (new findings surfaced during this pass)

Fixed 2026-06-12 (working tree, not yet committed).

- **Rotation deliveries have no apply-side monotonic guard** (`FIXED`) —
  `sync_engine.dart` `_applyConnectionCard` skips a delivery with
  `createdAt < follow.lastReceivedCardAt`, but `_applyRotatedFeedKey` has no
  such gate: a *replayed older* `new_feed_key` delivery (sealed bytes are
  valid — its key binds its own `createdAt`) re-applies and regresses
  `follow.feedKey` until the next genuine rotation delivery. Surfaced by the
  5c pipeline mapping; deliberately NOT changed during the refactor (semantic
  change). Fix: mirror the card path's monotonic gate on
  `follow.lastReceivedRotationAt`.
  **Fixed:** `_applyRotatedFeedKey` now early-returns when
  `delivery.createdAt < follow.lastReceivedRotationAt`, mirroring the card
  gate (strict `<`, so a same-second genuine re-rotation still applies; an
  inflated-timestamp replay still fails AEAD decrypt because the timestamp
  is bound into the key derivation). New `sync_engine_test` pins the replay:
  apply key A @5000 → key B @6000 → replay A's verbatim sealed delivery →
  `feedKey` stays B, `lastReceivedRotationAt` stays 6000.
