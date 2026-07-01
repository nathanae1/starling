# Plan 19 — UX: Flow Resilience & Polish

## Context

Second half of the pre-v1 UX review (see Plan 18 for the review's origin and the trust/liveness work). This plan hardens the two flows where the P2P/Tor medium bites hardest — **pairing** and **voice calls** — and then sweeps consistency and accessibility debt across the app.

The recurring theme: flows are built for the happy path where the other device answers within seconds. Over Tor, the normal case is "the other phone is asleep for hours," and today that reality surfaces as hangs, silent failures, and dead ends:

- A follow request to an offline friend **fails hard and discards the scanned card** — while the accept leg already has a durable retry queue (`retryQueuedAccepts`). The asymmetry is the bug.
- A voice call to an unreachable friend **spins forever**: no timeout exists anywhere in `RoomManager`/`WebRtcVoiceService`, signaling send failures are swallowed (`room_manager.dart:636-654` — the comment claims a retry round that doesn't exist), and an incoming call shows **8 hex chars of pubkey** and rings **silently**.

Depends on Plan 18 only for `friendlyError()` (Part C7) and the minute-ticker provider (Part B5); everything else is independent.

## Locked product decisions

| Decision | Choice |
|---|---|
| Outbound follow requests | **Durable queue, infinite retry** — mirror the accept leg's queue semantics exactly. Copy never blames the friend's setup ("no endpoints"); it says they look offline and we'll keep trying. |
| Call timeout | **60 s** per participant invite/offer → labeled terminal state ("No answer") with per-tile Retry. No global call abort. |
| Missed calls | Recorded as history rows on the invitee side and shown in Recent ("Missed · 2h ago"). No push — the foreground-only limitation is stated in the UI instead. |
| Destructive confirms | `showStarlingConfirm` with destructive styling is the single pattern. No stock `AlertDialog`s, no confirm sheets without Cancel. |

## Part A — Pairing flow resilience

### A1. Durable outbound follow-request queue
`follow_service.dart:213-219` throws `FollowFailure(noEndpoints)` when `probeCard` fails — the *normal* case (friend's phone unreachable over Tor). `confirm_request_sheet.dart:117-118` renders the misleading "they have no endpoints yet", and the scanned `ConnectionCard` is lost when the sheet closes.

- Persist the card as an outbound request with a `pending-send` status (outbound table + `deleteOutboundRequest` already exist; add the status value + stored card payload).
- Drive sends through the same retry-pump pattern as `retryQueuedAccepts` (`FollowRetryPump`, `lifecycle_manager.dart:112-116`) — retry on reachability transitions and periodic ticks.
- Sheet copy on unreachable: "They look offline right now — we'll keep trying and let you know." Sheet closes successfully; the Friends list shows the queued state (the accept leg already has this UI pattern: "accept queued / still retrying" + manual Retry — reuse it).

### A2. Handshake timeouts, Cancel stays enabled
`confirm_request_sheet.dart:81-83` disables Cancel while sending, and `HandshakeTransport.postFollowRequest` (`follow_service.dart:92-100`) has no `.timeout` — a stalled Tor circuit hangs "Sending…" forever. Add ~30 s timeouts to the handshake POSTs (request + accept legs), keep Cancel enabled throughout, and add the "This can take a minute over Tor" caption the relay-pairing sheet already has (`confirm_relay_pairing_sheet.dart:66-76`). On timeout → the A1 queue takes over ("we'll keep trying").

### A3. Scan feedback & permission dead ends
- `scan_screen.dart:69-70` silently ignores non-Starling QR codes — pointing at a wrong QR gives zero response. Show a transient "Not a Starling invite" overlay for `InvalidInvite`.
- No positive feedback on a successful scan: add `HapticFeedback.mediumImpact()` + brief success flash before the confirm sheet.
- `scan_screen.dart:57-63` — permanently-denied camera shows copy with no recourse. Add an "Open Settings" button (`openAppSettings()` from permission_handler) and re-run `_start()` on return. Keep the paste-invite fallback (it's good).
- Deep links: `main.dart:263-265` drops invalid invites silently; messaging apps truncate the long base64url links routinely. Surface "This invite link looks incomplete — ask your friend to re-send it," and add a "Request sent" toast on the success path (both callers currently ignore the sheet's result — `scan_screen.dart:74-79`, `main.dart:272-277`).

### A4. QR invite sheet
`qr_invite_sheet.dart`:
- Boost screen brightness / hold wakelock while the QR is visible (`wakelock_plus` is already a dependency; dim screens are the top cause of failed phone-to-phone scans).
- Add a system share action via `share_plus` (already used in `storage_settings_screen.dart`) alongside Copy link.
- One-line explainer for the one-directional handshake (`follow_service.dart:135-138`): "After they accept, have them show you their code too — that's how they share back."

### A5. Friends-list affordances
- Outbound pending rows (`friends_screen.dart:501-547`): add the request timestamp, a cancel action (wire the existing `deleteOutboundRequest`, `drift_storage_service.dart:633`), and fix the status label mapping (`'accepted' => 'Sent'` is confusing; raw status strings leak in the default branch).
- Accept button (`friends_screen.dart:170-176`): add an `_accepting` in-flight state (disable + "Accepting…") — it currently looks inert for the 15 s+ Tor probe and double-taps fire a second full accept.
- Reject (`friends_screen.dart:209-211`): confirm before deleting (it's irreversible and sits beside Accept); banner copy should suggest verifying the code with the friend since only `shortPubkey` identifies the requester.

## Part B — Voice hardening (`kVoiceEnabled` is on for v1)

### B1. Timeouts and labeled terminal states
- Per-participant invite/offer timeout (~60 s) in `RoomManager`: a participant still `connecting` past the deadline flips to a labeled state — "No answer" (invite never accepted) / "Couldn't reach" (signaling send failed, currently swallowed at `room_manager.dart:636-654`). `participant_avatar.dart:58-66` renders the label + a per-tile Retry that re-sends the invite/offer.
- Call-level hint while any peer is connecting: "Connecting over Tor — this can take a minute" on `active_room_screen.dart`.
- Distinguish `reconnecting` from `connecting` visually (`participant_avatar.dart:31-34` collapses them); attempt an ICE restart on `Failed` before declaring `disconnected` (`webrtc_voice_service.dart:244-246`).

### B2. Mic permission in the join path
- `incoming_invite_sheet.dart:49-61` — `_join`'s `catch (_) { pop() }` swallows everything including mic denial. Request `Permission.microphone` *before* `acceptInvite` (creator paths already do: `create_room_screen.dart:68`); surface failures ("Couldn't join the call") via `friendlyError()`.
- `active_room_screen.dart:35` — the fire-and-forget `Permission.microphone.request()` must check its result: denied → persistent "Microphone blocked — open Settings" banner with `openAppSettings()`; don't show "Live" (`:197-207`) while transmitting nothing.
- Both `isPermanentlyDenied` snackbars (`create_room_screen.dart:68-76`, `room_screen.dart:54-62`) get an Open Settings action.
- Join button double-tap: `_joining` flag disabling Join/Decline (currently a second tap causes a double pop via the swallowed `StateError` — `incoming_invite_sheet.dart:94`).

### B3. Caller identity + ring
`incoming_invite_sheet.dart:73` shows `creatorPubkey.substring(0, 8)`. `RoomManager._onInvite` (`room_manager.dart:388-406`) should resolve the creator's display name via its existing `_displayName()` helper and carry it on the invite. Play a repeating ringtone + vibration while the sheet is up (stop on answer/decline/expiry) — there is currently no audio/haptic anywhere in the voice path. Swipe-dismissing the sheet should send a decline (or timeout-decline) instead of leaving the creator's spinner running (`sheet.dart` `isDismissible: true` path).

### B4. Room lifecycle correctness
- `closeRoom` (`room_manager.dart:342-346`) sends `roomClose` only to `_present` — invitees who haven't answered keep a valid pending invite to a dead room. Send to the full invited roster; expire `_pendingInvites` after 60 s; a late accept surfaces "This call has ended."
- End-of-call: non-creators currently get a silent pop (`active_room_screen.dart:77-81`). Emit an end reason from `RoomManager` and show a brief "Call ended" snackbar.

### B5. Honest in-call state
- Participant count: `active_room_screen.dart:111-116` and `call_overlay.dart:21,44` count all participants including `connecting` invitees ("4 in call" before anyone answers). Count `connected` only, or "1 of 4 connected".
- Decline reasons: `room_manager.dart:441-445` maps decline/busy/full all to `disconnected` ("unreachable"). Propagate the reason into `VoiceParticipant` → tiles show "Declined" / "Busy" / "Room full".
- Mute sync on join: include current `muted` in the `roomAccept` exchange (`room_manager.dart:303-316,408-439`) so new joiners see real mute states.
- Call duration: ticking `mm:ss` in the active-screen header and the overlay (`VoiceRoom.createdAt` already exists).
- Speaking indicators: `webrtc_voice_service.dart:250-267` takes the max audio level over *all* stats reports including the local `media-source`, so your own voice lights up remote rings. Filter to `inbound-rtp` per remote; add a self-level entry keyed by own pubkey ("my mic works" feedback).
- Wakelock: tie to `voiceRoomStateProvider != null` (e.g. in `AppShell`) instead of active-screen mount (`active_room_screen.dart:32,40`) so navigating to the overlay doesn't let the phone lock mid-call.

### B6. Missed calls & the foreground-only truth
- Invitee side: write a history row on invite expiry/busy-auto-decline (`room_manager.dart:379-387`; sheet expiry at `incoming_invite_sheet.dart:38-41` currently just pops) → Recent list shows "Missed · 2h ago".
- Invalidate/stream `recentVoiceRoomsProvider` (`voice_provider.dart:90-93`) on call end — today a just-finished call doesn't appear until app restart.
- Make Recent rows tappable → re-create a room with the same participants (`room_list_screen.dart:188-232` rows are inert).
- One-line explainer on the Rooms screen: "Calls ring only while Starling is open."
- Guard against stacked invite sheets (`app_shell.dart:79-84` shows one per emission; only mid-call is auto-declined) — track sheet-open state, auto-decline the second with `busy`.

## Part C — Consistency & accessibility sweep

### C1. Dialog/confirm consistency
- Unfollow on other-profile: stock `AlertDialog` with equal-weight buttons (`other_profile_screen.dart:207-223`) → `showStarlingConfirm(destructive: true)`.
- Post delete: destructive-style the Delete action (`post_actions_sheet.dart:57-60`); add an in-flight state + error surfacing around `deletePost` (`:67-73`).
- Relay unpair sheet: add Cancel + destructive styling (`connection_settings_screen.dart:233-258`).
- Unfollow/clear-cache/export long ops get progress indicators (`friend_actions_sheet.dart:53-86` key-rotation wait; `storage_settings_screen.dart:79-130` `_busy` is grey-out only); clear-cache confirm shows the size it frees (`cachedFromOthersBytes` is already computed).

### C2. Settings: Account section
`settings_screen.dart:50-81` has no account block. Add: **View recovery phrase** (re-derive/retrieve via `KeychainManager`, gated behind local auth — Face ID/biometric prompt), app version/about. (Reset-identity flow deferred — bigger than UX.) Fix the duplicated "NETWORK / Network" label scent (`:53-59`).

### C3. Accessibility batch
- `welcome_screen.dart:51,94`: `RichText` → `Text.rich` so the headline and the restore link honor system font scaling.
- Missing `Semantics`: post-card tap target (`post_card.dart:75`), avatar picker (`setup_screen.dart:102-137`), participant tiles — name/muted/speaking/connecting (`participant_avatar.dart:37-98`), call overlay "Return to call" (`call_overlay.dart:30`), QR image (`qr_code.dart:23-36` `semanticsLabel`), scan close button (`scan_screen.dart:175-178`), address-row copy action (`starling_address_row.dart:27`), profile post-grid cells (`own_profile_screen.dart:297`, `other_profile_screen.dart:251`).
- Disabled-button semantics: `_StarlingButton` disabled state is opacity-only (`buttons.dart:52`) — add `Semantics(enabled: false)`; loading labels ("Creating…", "Restoring…") get an inline spinner via the existing `leading` slot.

### C4. Navigation & layout
- Onboarding back-stack: `push` (not `go`) into setup/restore so Android system back returns to Welcome instead of exiting (`router.dart:57-76`, `welcome_screen.dart:81,86`); recovery stays forward-only deliberately.
- Setup screen: wrap in the `Expanded > SingleChildScrollView` pattern the recovery screen already uses (`setup_screen.dart:80-156` overflows with the keyboard on small phones).
- Other-profile post grid: pass a route prefix like own-profile does (`routePrefix`, `own_profile_screen.dart:284`) so posts opened from the Friends tab don't push onto the Feed branch (`other_profile_screen.dart:252`).

### C5. Content & copy
- Caption: `maxLength` + counter in compose (`StarlingTextarea` already supports it, `inputs.dart:75`); feed cards clamp to ~4 lines with "more" opening the detail (`post_card.dart:150-161`).
- Display name: length cap (~50) + `TextCapitalization.words` (extend `StarlingInput`); clamp in `publishProfile` like bio (`profile_service.dart:122-127`).
- Network screen jargon rewrite for non-technical users (`network_settings_screen.dart`): "Bootstrap/Circuits" → "Connecting to Tor / Connected"; drop "0.0.0.0", "WorkManager", "endpoints" from user-facing copy.
- Empty states: profile post grids render literally nothing when empty (`own_profile_screen.dart:281-283` — add compose CTA; `other_profile_screen.dart:237-239` — "No posts yet / nothing synced yet"); friends-list loading no longer collapses to "No friends yet" (`friends_screen.dart:33-38`).
- Comment input: use the real profile avatar instead of `Avatar(name: 'You')`; allow multiline (`comment_input.dart:74`, `inputs.dart:33`).
- Post detail: use `EncryptedAvatar` in the header like the feed card (`post_detail_screen.dart:202`); make the inert comment icon focus the comment input (`:275-279`); scroll to reveal a just-posted comment.

### C6. Recovery-phrase hardening (carry-over from review)
- Clipboard: auto-clear ~60 s after copy + "clears in 60 seconds" in the snackbar; fix the `_copied` reset racing the snackbar duration (`recovery_phrase_screen.dart:22-54`).
- `FLAG_SECURE` on Android while the phrase route (and the Plan 19 settings re-display) is visible — the screen currently says "Don't screenshot it" with no enforcement.
- Avatar cropper: `interactive: true` + `fixCropRect: true` so "Move and scale" is true (crop_your_image defaults `interactive` to false — `avatar_crop_screen.dart:58,70-83`); or change the copy.
- Voice settings save: report parse results ("3 servers saved, 1 line skipped") instead of unconditional success (`voice_settings_screen.dart:42-54`).
- `sheet.dart:18-21`: dispose the per-call `transitionAnimationController` (leak found during review; not UX-visible but fix while touching sheets).

## Don't regress (verified good)

Paste-invite fallback on the scan screen; queued-accept states + manual Retry; leave-call confirmation with creator-specific copy ("Leaving will end it for everyone"); mute/route `_CircleControl` semantics; overlay + FAB collision handling (`app_shell.dart:70-73`); Android foreground-service mic-type sync (`app_shell.dart:90-97`); relay sheet's "can take a minute" caption (now the template for A2).

## Verification

- `flutter analyze` + `flutter test` (new tests: outbound-queue retry semantics, invite timeout state machine, decline-reason mapping).
- Two-device pairing: scan a friend whose app is closed → sheet succeeds with "we'll keep trying", Friends list shows queued state, delivery completes when the friend opens the app; cancel a pending request; reject with confirm.
- Voice: call an offline friend → tiles resolve to "No answer" at ~60 s with Retry; callee backgrounded → missed-call row appears in Recent; decline → "Declined" tile; incoming call rings audibly and shows the caller's name; creator ends call → invitee's stale invite says "This call has ended"; mid-call network blip → "Reconnecting…" then recovery or labeled failure.
- Accessibility: VoiceOver/TalkBack pass over feed cards, participant tiles, QR sheet, avatar picker; system font scaling at max on Welcome.
- Screenshot attempt on the recovery-phrase screen (Android) is blocked; clipboard clears after 60 s.
