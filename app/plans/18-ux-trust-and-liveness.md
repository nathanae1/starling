# Plan 18 — UX: Trust & Liveness

## Context

A full pre-v1 UX review (2026-07) swept every screen plus the network/status layer. The headline: the app does a lot of honest engineering work — retry queues, reachability probes, Tor bootstrap percent, sync error capture — that the UI either never shows or shows incorrectly. The review produced ~60 verified findings (every one checked against the code, several re-verified by hand), split into two plans:

- **Plan 18 (this one) — trust & liveness.** Everything with data-loss or "app looks broken" stakes: critical onboarding/pairing/profile bugs, the connectivity status light, and feed reactivity. Mostly provider/state-layer work.
- **Plan 19 — flow resilience & polish.** Pairing-flow hardening, voice-call hardening, and the consistency/accessibility sweep. Screen-level work that can land independently after this plan.

Three findings anchor this plan:

1. **The recovery-phrase screen can be skipped by a router race** — a user can finish onboarding never having seen the one artifact that can recover their account (viewable nowhere else in the app).
2. **The feed never shows synced content without a manual pull-to-refresh** — `feedProvider` is a one-shot future that background syncs, tab-tap syncs, resume syncs, and inbound pushes never invalidate. The app syncs; the UI doesn't know.
3. **The status row lies.** Tor bootstrap (10–30 s cold start, `lifecycle_manager.dart:123`) is invisible in the main UI; the feed's "Offline — tap to retry" is computed from the mDNS LAN cache only (so away-from-home users see "Offline" forever while Tor sync works fine); sync errors are captured but displayed nowhere; "Last synced just now" is a hardcoded string.

## Locked product decisions

| Decision | Choice |
|---|---|
| Feed liveness mechanism | **Drift `.watch()` reactive streams** at the storage layer, not sync-triggered invalidation. Content appears live regardless of which path stored it (sync pull, inbound push, background sync). |
| Status vocabulary | Four states: **Connecting** (Tor bootstrapping, no peers reachable yet) → **Synced/Up to date** → **Offline** (no friend reachable on *any* transport) → **Sync problem** (last run errored). "Reachable" is defined by `PeerReachabilityMonitor` (LAN + Tor + libp2p), never by mDNS alone. |
| Error copy | Users never see raw `Exception`/`StateError` strings. One `friendlyError()` helper maps known failures to human copy; raw detail goes to `debugLog`. |
| Recovery phrase gate | Checkbox confirm ("I've written these words down") — no spot-check quiz in v1. Re-display in Settings is Plan 19 (Account section). |

## Part A — Critical fixes (small, surgical)

### A1. Recovery-phrase redirect race (CRITICAL)
`router.dart:52-55` bounces every onboarding route except `/onboarding/done` to `/feed` once `hasIdentity` is true. `createIdentity()` (`onboarding_provider.dart:98`) invalidates the identity provider *before* `setup_screen.dart:57` navigates to `/onboarding/recovery`; when the async reload lands, `_IdentityRefresh` re-runs the redirect and yanks the user off (or past) the recovery screen.

- Exempt `/onboarding/recovery` exactly like `/onboarding/done`: `state.matchedLocation != '/onboarding/done' && state.matchedLocation != '/onboarding/recovery'`.
- Gate the setup screen's back arrow while creating: `setup_screen.dart:83-87` → `onPressed: _creating ? null : ...`. (Otherwise back-during-create lands on Welcome and the same redirect skips recovery even with the exemption.)
- Widget test: pump the router, create identity, resolve the identity reload, assert location stays `/onboarding/recovery`.

### A2. Restore-field input hygiene
`restore_screen.dart:97-136` — the phrase TextField leaves autocorrect and suggestions on: the OS mangles words *and* the 24 secret words feed the keyboard's learning dictionary. Add:
`autocorrect: false, enableSuggestions: false, smartDashesType: SmartDashesType.disabled, smartQuotesType: SmartQuotesType.disabled, textCapitalization: TextCapitalization.none` (keep multiline compatibility — `maxLines: null`).

### A3. Phrase confirm gate
`recovery_phrase_screen.dart:147-156` — "I wrote it down" is one unguarded tap that calls `clearRecoveryPhrase()` forever. Add a checkbox row ("I've written these 24 words down somewhere safe") that gates the primary button's enabled state.

### A4. Friendship demotion on re-scan
`follow_request_handler.dart:83-90` saves every inbound request via `insertOnConflictUpdate` with default `status = 'pending'` (`types.dart:295`), so re-scanning an existing friend's QR flips their accepted row back to pending — the "Follows you" state vanishes and `isAcceptedFollower` breaks during the window.

- Handler: before saving, read the existing inbound row; if its status ≠ `'pending'`, no-op (or refresh endpoints only — never downgrade status).
- Sender side: `ConfirmRequestSheet` checks `getFollow(card.pubkey)` / existing outbound row and shows "You're already friends with this person" instead of offering to re-send.

### A5. Self-scan guard
`scan_screen.dart:66-79` / `confirm_request_sheet.dart` never compare `card.pubkey` to the user's own identity — scanning your own QR (the obvious first experiment) sends a follow request to yourself. Detect in `_handleScan` (and the deep-link path) → snackbar "That's your own code — have a friend scan it instead."

### A6. Avatar silent delete on profile save
`edit_profile_screen.dart:43,74-93` — `_avatarBytes` starts null and fills only after the existing avatar downloads+decrypts; Save is enabled the whole time (`_canSave` ignores `_loadingAvatar`), and `profile_service.dart:102-120` omits `avatarHash` when bytes are null. Editing your bio while the avatar is loading (or after its fetch failed) publishes a profile with no avatar — deleted for all followers, silently.

- Track avatar state as an enum: `unchanged | replaced(bytes) | removed`. On `unchanged`, reuse the existing `avatarHash` (no re-encode — also fixes generational JPEG loss from round-tripping the decrypted thumbnail).
- Block Save (or just avatar-affecting saves) while `_loadingAvatar`; if the current avatar failed to load, say so instead of proceeding as if none exists.

### A7. Compose cancel vs. back inconsistency
`compose_screen.dart:37-40` — Cancel invalidates the draft instantly (photo + caption gone, no confirm); the system back gesture pops without invalidating, so the keepAlive draft (`compose_provider.dart:70`) silently survives. Pick one policy: when dirty (`caption.isNotEmpty || photoBytes != null`), both Cancel and system back (via `PopScope`) show "Discard post?"; discard invalidates, keep returns to compose.

## Part B — Connectivity status light

### B1. `torStatusProvider` — make Tor status observable
`ArtiTorService.getStatus()` already returns `bootstrapPercent` / `isReady` / `circuitCount` (`services/tor/arti_tor_service.dart`), but the only consumer calls it once per widget build (`network_settings_screen.dart:36-37`) — a frozen snapshot. Add a polled provider (new `providers/tor_status_provider.dart`):

- Stream provider that polls `tor.getStatus()` every 1 s while `!isReady`, dropping to ~10 s once ready (circuit count still changes). Emit only on value change to avoid rebuild churn.
- `NetworkSettingsScreen` watches it instead of calling `getStatus()` directly — fixes the frozen bootstrap % for free.
- `MockTorService` (`services/mocks/mock_tor_service.dart:50`) already returns a static status; no changes needed for tests.

### B2. `SyncState.connecting` — the status light itself
`SyncDot` (`widgets/sync_dot.dart`) is well built (distinct glyph + color + semantics label + pulse for in-flight). Add a fourth state:

- `SyncState.connecting` — glyph `LucideIcons.loader` (or similar), sage color, pulsing like `syncing`, semantics "Connecting".
- `syncStatusProvider` enters `connecting` when: Tor is not ready (`torStatusProvider`) **and** no friend is currently reachable **and** follows exist. Label in `FeedSyncSearchBar`: `"Connecting to network… 43%"` (percent from `torStatusProvider`; omit the number if 0).
- Once Tor is ready or any peer is reachable, fall through to the existing synced/offline logic.

### B3. Rebase "reachable" on the real monitor
`sync_status_provider.dart:36-39` counts reachable friends from `discoveryControllerProvider` — the mDNS LAN cache only (`discovery_provider.dart`). Friends reachable over Tor count as unreachable, so the feed shows "Offline — tap to retry" forever whenever no friend shares your LAN.

- Watch `peerReachabilityStateProvider` (`sync/peer_reachability_provider.dart:57-62`) — it already streams per-pubkey reachability across LAN/Tor/libp2p, seeded with the monitor's snapshot.
- `reachable = follows.where((f) => reachabilityMap[f.pubkey]?.isReachable ?? false).length` (adapt to `PeerReachability`'s actual shape).
- `SyncState.offline` then means *actually* unreachable on every transport.

### B4. Surface sync errors
`SyncController` stores `lastError` (`sync_provider.dart:265`); comments at `app_shell.dart:44` and `feed_sync_search_bar.dart:59` claim "errors surface via syncStatusProvider" — but that provider never reads it. Make the comments true:

- Add `lastError` (or a `hasError` flag + message) to `SyncStatus`; `syncStatusProvider` watches `syncControllerProvider` for it (it already watches the phase).
- `FeedSyncSearchBar`: when the last run errored and we're not syncing, show "Sync problem — tap to retry" (reuse the existing tappable-row + retry plumbing built for offline, `feed_sync_search_bar.dart:127-141`). Copy stays friendly; raw error goes to `debugLog`.

### B5. Honest relative time + shared ticker
`feed_sync_search_bar.dart:187-207` returns the hardcoded string "Last synced just now" for any non-null timestamp, and the "N/M friends reachable" fraction sits on a dead branch (only renders before the first sync ever completes).

- Add a shared `minuteTickerProvider` (StreamProvider emitting every 60 s).
- Status label: "Up to date · synced 4m ago" (compute from `lastSyncedAtSeconds`, rebuild on tick); show "N/M friends reachable" as the *primary* synced-state label when totalFriends > 0, with last-synced as the secondary clause — inverting the current dead-branch logic.
- Reuse the ticker for `timeAgo` in `post_card.dart:120-124`, `comment_list.dart:106-111`, friends-list last-seen (`friends_screen.dart:323-325` — which should also read `peerReachabilityStateProvider` for its "● Reachable" dot instead of `now - lastSyncedAt < 60` computed once at build), and other-profile presence (`other_profile_screen.dart:134-187`).

## Part C — Feed reactivity & core-loop feedback

### C1. Reactive queries (the single biggest UX win)
`feed_provider.dart:26-31` is a one-shot future over `storage.getFeedEvents()`; the only invalidations are the user's own actions (`feed_screen.dart:63` pull-to-refresh, `preview_screen.dart:38` own publish, `post_actions_sheet.dart:68` own delete). Nothing that *receives* content — `SyncController`, `events_push_handler`, `ReconnectPusher`, background sync — touches UI providers. Same for `commentsProvider`/`reactionsProvider` (only invalidated by the local user's own comment/react).

- Storage layer (`drift_storage_service.dart` + `daos/events_dao.dart`): add `watchFeedEvents()`, `watchEventsByRef(ref, kind)`, `watchProfilePosts(pubkey)` built on drift's `.watch()` over the same queries the `get*` variants use. Drift streams re-emit on any write to the watched tables, regardless of which isolate/path wrote (background isolate writes: verify — if background sync uses a separate DB connection, the stream won't fire; acceptable, since the app re-syncs on resume anyway).
- Providers: `feed`, `commentsFor`, `reactionsFor`, `ownPosts`, `profilePosts` become stream providers. Riverpod's default `skipLoadingOnRefresh`/stream seeding keeps counts from flashing to zero (verified behavior in the review).
- Keep the existing `ref.invalidate` calls initially (harmless), remove once streams are proven.
- Interface: extend `StorageService` (`services/storage_service.dart`) + `MockStorageService` with the watch methods.

### C2. Pull-to-refresh timeout
`feed_screen.dart:54-65` awaits the full multi-peer sync (unbounded — minutes over Tor with offline friends). Race `syncNow()` against ~6 s: `await Future.any([syncFuture, Future.delayed(...)])`; release the `RefreshIndicator`, let the status row's "Syncing…" carry the rest. With C1, results appear live when the sync finishes.

### C3. Recoverable feed error state
`feed_screen.dart:78,201-221` — the error state is a non-scrollable `Center` (so `RefreshIndicator` can't arm; no in-UI recovery) showing raw `'$e'`. Wrap in a `ListView` with `AlwaysScrollableScrollPhysics` (pattern already used by `_EmptyScroll`), add a Retry button that invalidates `feedProvider`, use `friendlyError()` copy.

### C4. Comment failures + attribution
- `comment_input.dart:37-50` — `_submit` has no catch: on failure the send button just appears to do nothing. Catch → inline error/snackbar "Couldn't post your comment — try again" (text already survives; keep that).
- `comment_list.dart:77-80` — while a friend's profile loads, `orElse: () => 'You'` labels *their* comment as yours. Compare `comment.pubkey` against own identity pubkey for the "You" label; loading/error fallback becomes `'Friend'` (consistent with `post_card.dart:64`).

### C5. Encrypted image loading & failure states
`encrypted_image.dart:107-121` — during a fetch+decrypt that can take 30 s+ over Tor (`media_decrypt.dart:74-86`), the tile is a flat linen rectangle; terminal failure says "Tap to load" even when the real cause is "friend offline" (tapping can't fix it), and permanently-undecryptable legacy rows (`media_decrypt.dart:161-164`, `msgSeq == null`) look identical.

- Pending: subtle pulse/shimmer on the placeholder (reuse the SyncDot triangle-wave opacity pattern).
- Failure copy differentiated: "Photo will load when your friend is next online" (peer unreachable) vs. "Tap to retry" (transient) vs. nothing-actionable for legacy rows.
- Auto-retry when the author becomes reachable: listen to `peerReachabilityStateProvider` for the author pubkey instead of relying on a manual tap.

### C6. Liked heart
`reaction_button.dart:73` — `widget.liked ? LucideIcons.heart : LucideIcons.heart`: both branches identical; liked is color-only (invisible to color-blind users). Render a filled heart when liked (lucide has no filled variant — either draw the glyph twice with a `Paint`-filled icon, use `Icons.favorite`, or stack a lower-opacity filled backdrop); include the count in the semantics label ("Unlike. 3 likes").

### C7. `friendlyError()` pass
New `utils/friendly_error.dart`: maps known failure types (FollowFailure, TorServiceException, timeouts, StateErrors from mutual-follow checks) to human copy, returns a generic "Something went wrong" otherwise, and `debugLog`s the raw error. Replace every user-facing `'$e'`:
`setup_screen.dart:63`, `feed_screen.dart:78`, `post_detail_screen.dart:62`, `comment_list.dart:36`, `create_room_screen.dart:60,90`, `room_screen.dart:76`, `own_profile_screen.dart:50`, `other_profile_screen.dart:61-90`, `connection_settings_screen.dart:44`, `storage_settings_screen.dart:126,180`, `edit_profile_screen.dart:156`, `preview_screen.dart:56` (also stop storing raw `$e` via `markPublishFailed`), `scan_screen.dart:118-122` (raw parser reasons → "That doesn't look like a Starling invite").

## Don't regress (verified good)

Restore-screen error handling (cause-specific copy, word-count caption, error-clear-on-edit); double-submit guards on publish/restore/create; queued-accept retry states + manual Retry in the friends list; Tor-not-ready gating on send buttons; SyncDot's glyph+color+semantics construction; image compression pipeline (1080 px isolate re-encode); decoded-image LRU cache.

## Verification

- `flutter analyze` + `flutter test` (update widget tests that enumerate `SyncState` values and the feed bar labels; add the A1 router race test).
- On device/simulator:
  - Onboarding: create identity → recovery screen persists (no bounce), back gated during create, checkbox gates continue. Restore: type phrase words with autocorrect-prone spellings — no mangling.
  - Pairing: re-scan an existing friend → "already friends", their side stays accepted. Scan own QR → friendly rejection.
  - Profile: open Edit profile on a slow connection and save immediately → avatar survives.
  - Status: cold-start → feed bar shows "Connecting to network… N%" → transitions to synced; airplane mode → honest "Offline"; kill the peer and sync → "Sync problem — tap to retry"; idle 10 min → "synced 10m ago" ticks.
  - Liveness (two devices or device + relay): post from A; B's feed shows it without pull-to-refresh; comment from A while B sits on the post detail → appears live.
