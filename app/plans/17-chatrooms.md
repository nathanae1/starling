# Plan 17 — Chatrooms

## Context

Plan 16 shipped voice rooms as an **ephemeral, signaling-plane** feature: a room exists only while a call is live, persists only as local-only call history, and an invite is a real-time frame that vanishes if the recipient's app isn't open. That's a *synchronous phone call* model bolted onto an app that is otherwise async-first (seconds-to-hours feed sync over Tor) — and it has none of a phone call's guarantees (no push, no server, no missed-call record). The result: cold-calling people who usually can't receive the invite, failing silently.

Plan 17 reframes the primitive to match the medium. A **room becomes a durable place**: a long-lived (optional), unbounded-membership chatroom with an async, E2E-encrypted **text timeline** that syncs between members like the rest of the feed. Each room can host **one live voice call at a time**; starting a call **pings every member** — reachable members get the in-app prompt now, offline members see a durable "call started" message on next sync. The Plan 16 voice mesh is reused unchanged for the call itself.

This keeps every project constraint intact: no servers, no push, privacy-first. Crucially, **text chat is completely silent** — reading or posting leaks nothing about who is online. The *only* moment a user broadcasts presence is when they **join a room's live call**, and only to that call's participants.

**Prerequisites (all landed):** 07 (HTTP server), 08 (follow/key exchange), 09 (LAN sync), 10 (comments/reactions — the delivery template), 11/11b/11c (Tor + signaling), 13 (sealed feed-key rotation), 14 (foreground service), 16 (voice rooms — the call engine).

## Locked product decisions

| Decision | Choice |
|---|---|
| Text-chat room size | **No maximum.** Membership is unbounded. |
| Live-call size | **≤ 4** (Plan 16 full mesh). 5th+ to join an active call is declined `reason: 'full'`. |
| Membership admin | **Creator only.** The creator is the single signed authority for add/remove and key rotation. Multi-admin deferred. |
| New-member history | **Include prior history.** A new member is backfilled and can read past messages. ⇒ room key rotates **only on remove**, never on add. |
| Membership gate | Accepting into a room is restricted to **mutual follows** (reuse `RoomManager._isMutualFollow`). |
| Text content (v1) | UTF-8 text only; media deferred. |

## The load-bearing insight

A chatroom is structurally **"a post that many people can comment on,"** with three substitutions:

| Comments (existing, Plan 10) | Chatrooms (new) |
|---|---|
| post (kind 1) is the thread root | genesis `roomCreate` (kind 100); its event id **is** the `roomId` |
| comment (kind 4), `ref = postId` | `roomMessage` (kind 102), `ref = roomId` |
| encrypted under author's **feed key** (broadcast to all followers) | encrypted under the **room key** (membership-scoped) |
| delivered to the **post's author** via the outbound queue | delivered to **every other member** via the outbound queue |
| read via `getEventsByRef(postId, kind: comment)` | read via `getEventsByRef(roomId, kind: roomMessage)` |

So the **read path** (`getEventsByRef`, the comments allow-list/tombstone filter), the **local storage path** (`event_entries`, `saveEvent`, `getEncryptedPayload`), and the **directed delivery transport** (`enqueue` → `outbound_drain` → `POST /events` → `ingestPushedEnvelope`) are all reused. Only two things genuinely change: the **encryption key** (room key, not feed key) and the **delivery target set** (all members, not one author).

The per-message crypto is already parameterized: `feed_key_ratchet.deriveMsgKey(chainRoot, msgSeq)` and `PairwiseContentKeyService.encryptEvent(event, chainRoot, epoch, msgSeq)` take an *explicit* chain root. Passing the room key instead of `identity.feedKey` is the whole crypto change — no new ratchet code.

## Architecture

| Plane | Carries | Durability | Transport |
|---|---|---|---|
| **Durable room** (text, membership, room key, "call started" record) | `roomCreate/roomMembership/roomMessage/roomCallStarted` events | persisted + synced | outbound-queue fan-out → `POST /events` (Plan 10 transport) |
| **Live call** (invite/SDP/ICE/mute + presence) | `SignalingMessage`s | ephemeral (±30s) | Plan 16 signaling + WebRTC mesh |

Two keys, two scopes, never conflated: the **durable room key** (membership-scoped, encrypts text, rotates on remove) and the **ephemeral per-call `session_key`** (Plan 16 call-membership token; audio is DTLS-SRTP).

## Design

### 1. Room as a durable, synced object — new `EventKind`s (100–199 messaging range)

In `lib/models/event_kind.dart` (add as defined kinds; `isKnown` stays 1..6 — it has no consumers, so new kinds flow through storage/sync ungated):

- **`roomCreate = 100`** — genesis. Its `id` **is** the `roomId` (content-addressed, identical for every member). Content (CBOR) `{name, creatorPubkey, createdAt}`. Signed by creator, encrypted under the room key.
- **`roomMembership = 101`** — `ref = roomId`, content CBOR `{members:[pubkey…], membershipEpoch, roomKeyEpoch}`. The durable signed roster (analogue of `followList=3`). Applied **only if `event.pubkey == creatorPubkey`** and `membershipEpoch` is newer. Members never author these in v1.
- **`roomMessage = 102`** — `ref = roomId`, content = UTF-8 text (mirrors comment). Also set `extensions['room'] = roomId` bytes (hashed into id; forward-compat).
- **`roomCallStarted = 103`** — `ref = roomId`, content CBOR `{callId, starterPubkey}`. The durable "Alice started a call" record offline members see on sync.

### 2. Per-room key management

- **Mint:** creator generates a 256-bit room key (`crypto.randomBytes(32)`), epoch 0, `roomMsgSeqCounter = 0`, stored per-room in a new `rooms` table (the per-room analogue of `identity.feedKey`/`feedKeyEpoch`/`msgSeqCounter`).
- **Seal — bypass `SealedDeliveryChannel`, reuse the raw seal primitives.** `SealedDeliveryChannel` assumes one pending stream per recipient and a fixed **two-slot manifest ack** (`manifest_ack.dart`: `ack_rotation_at`/`card_seen_at`); a user is in many rooms, needing a `(recipient, roomId)` dimension it can't express. Instead reuse the standalone `sealDeliveryPayload(...)` / `unsealDeliveryPayload(...)` (X25519 `starfk00` DH-seal, independent of manifest plumbing) and deliver the sealed key over the **outbound queue** as a typed `room-key` item (§3). The queue already does many-per-recipient + retry.
- **Encrypt under a room-scoped MegOLM chain:** reuse `feed_key_ratchet.dart` unchanged. Add one method to `ContentKeyService` (+ `PairwiseContentKeyService` + mock): `signAndEncryptForRoom(Event event, {required Uint8List roomKey, required int roomEpoch, required int roomMsgSeq})` — reuses `computeEventId` + author Ed25519 `sign` + `encryptEvent(signed, roomKey, roomEpoch, roomMsgSeq)`. Signing (author key) and encryption (room key) stay cleanly separated; `Audience.group` stays reserved.
- **Rotate — only on remove(X)** (mirror `key_rotation_service.dart`): (1) archive current key to `room_key_history` window `[validFrom, now)`; (2) mint fresh key, epoch 0, reset `roomMsgSeqCounter`, bump `roomKeyEpoch`; (3) seal new key to each *remaining* member (exclude X) via `sealDeliveryPayload` → enqueue `room-key`; (4) author a new `roomMembership` without X and fan it out. Removed member keeps the old key (reads history) but cannot read post-rotation messages (**backward secrecy**).
- **Add(N):** seal the **current** key to N (so N reads existing history — the locked "include prior history" choice) + author `roomMembership` including N. **No rotation on add.** History catch-up = §3 replay.
- **Decrypt candidate-key selection** mirrors `SyncEngine._processEventItem`: try current room key, then `room_key_history` rows whose `[validFrom, validUntil)` covers the message's `createdAt`.

### 3. Durable message delivery / convergence

**v1 = outbound-queue fan-out + bounded history replay.** Room-scoped pull is deferred (Phase H). Rationale: the outbound queue (`enqueue` → `drainOutboundQueueForPeer` → `POST /events` → `ingestPushedEnvelope`) is the proven Plan 10 directed-delivery transport; it is durable, offline-tolerant (retries on transport failure; drops only after 3 *4xx* rejections), and per-recipient. An offline member converges fully on reconnect — identical to the guarantee comments already ship.

Concrete plumbing:
- **Typed queue items.** Add a nullable `itemType` column to `OutboundQueueEntries` (default `'event'`). **`outbound_drain.dart` currently hardcodes `EnvelopeItem(type:'event')` (line 45)** — generalize it to read `itemType` per row. Keep the existing `isFollowAcceptQueueEntry` exclusion. (Hot, retry-sensitive path — change carefully.)
- **Authoring** (`RoomMessageService`, mirrors `DefaultCommentService`): hold the `PublishLock`, allocate `roomMsgSeqCounter` from the room row, `contentKey.signAndEncryptForRoom(...)`, `saveOwnEventWithEncrypted` (→ `isOwn=1`, re-servable), bump `roomMsgSeqCounter`, then **fan-out enqueue** the wire bytes as `room-event` items to every other current member (`getRoomMembers(roomId)` minus self).
- **Ingestion:** extend `ingestPushedEnvelope` (`events_push_handler.dart`) with `case 'room-key'` and `case 'room-event'` → new `lib/server/handlers/room_ingest.dart`. **Process `room-key` before `room-event` within an envelope.** Auth: accept `room-key` only if it unseals (possession proof) AND sender is a mutual follow; accept `room-event` only if we hold the room key for its `roomId` AND the inner author is a current member. Decrypt (current + history keys), `saveEvent` (→ `isOwn=0`), `updateRoomActivity(roomId, createdAt)`. Old clients preserve unknown item types (already in place).
- **Late-joiner replay:** on add(N), the admin enqueues its newest **K** `roomMessage` events (reusing stored room-key wire bytes) to N as `room-event` items. Bounded — full backfill awaits Phase H.
- **Ordering / dedup:** timeline ordered by `(createdAt, id)` (same as comments); dedup by event id on `saveEvent`. Eventually-consistent, no causal/Lamport ordering in v1 (matches comments).

**⚠️ Required isolation (security-relevant leak fix).** A `roomMessage` I author has `ref = roomId` and `isOwn=1`, so `getOwnAndIncomingRefs(me)` includes it and `buildEventsEnvelope` (`events_handler.dart:82-96`) would **re-encrypt it under my feed key and serve it to all my followers**; `manifest_handler` would also list it. That leaks room metadata and breaks membership-scoping. **Fix: exclude kinds 100–103 from the broadcast-serving seams** — `getOwnAndIncomingRefs`/`buildEventsEnvelope` (`events_handler.dart`) and the manifest event list (`manifest_handler.dart`).

**⚠️ Scalability of "no maximum" membership.** Push-fanout costs **O(members) directed deliveries per message**. Fine for modest rooms; large rooms strengthen the case for the deferred pull plane (Phase H). v1 ships fanout; document a soft practical guidance and revisit if rooms grow large.

### 4. The single live call per room

"Start call" does two things, in order:
1. **Durable ping:** author `roomCallStarted` (kind 103) and fan it out via §3. Offline members see "Alice started a call" on next sync — the no-server, no-push durable notification.
2. **Live ping (the ONLY presence broadcast):** fan a `roomInvite` `SignalingMessage` to all other members via `RoomSignaling.fanOut(...)`. Reachable members get the existing global invite sheet (`incomingVoiceInvitesProvider` → `showIncomingInviteSheet` in `app_shell.dart`); unreachable ones fail silently inside `FanOutException` and rely on the durable record. No beacon, no heartbeat — presence is emitted only here and at call-join, only to members.

- **Size:** room membership unbounded; the call stays the Plan 16 full mesh ≤ 4. Add `RoomManager.startRoomCall(roomId, memberPubkeys)`; **enforce the 4-cap on accept** (decline `reason:'full'` once `_present` hits 4). The call's signaling `roomId` = the chatroom `roomId`. The call `session_key` stays the ephemeral per-call key, separate from the durable room key. RoomManager/RoomSignaling/VoiceService cores unchanged otherwise.
- **One call / glare:** key the call signaling `roomId` to the chatroom `roomId`; `RoomManager` already blocks a second `createRoom` and de-dups accept/offer gossip, so concurrent starts mostly converge. Residual two-mesh glare is a flagged v1 limit (tiebreak on lowest `callId`/earliest `roomCallStarted.createdAt` if observed).
- **⚠️ Plan 16 id conflation:** the `voice_rooms` history PK is the call id; reusing the chatroom `roomId` would make a second call `insertOrReplace`-overwrite the first. Give call-session history a **distinct `callId` domain** (or drop per-call history in v1).

### 5. Storage (schema v8 → v9)

Messages **reuse `event_entries`** (kinds 102/103, `ref=roomId`) — no new message table. New tables for room identity/keys/members:

- `tables/rooms_table.dart` — `RoomEntries`: `id`(=roomId,PK), `name`, `creatorPubkey`, `createdAt`, `lastActivityAt` (retention key, **not** createdAt), `roomKey`(BLOB), `roomKeyEpoch`, `roomKeyValidFrom`, `roomMsgSeqCounter`, `membershipEpoch`, `isMember`, `lastReadAt`.
- `tables/room_members_table.dart` — `RoomMemberEntries`: PK `(roomId,pubkey)`, `displayName?`, `addedAt`, `removedAt?`, `role`.
- `tables/room_key_history_table.dart` — `RoomKeyHistoryEntries`: PK `(roomId,epoch)`, `roomKey`, `validFrom`, `validUntil` (mirror `follow_feed_key_history_table.dart`).
- `daos/rooms_dao.dart` (mirror `voice_rooms_dao.dart`): upserts, member/key-history queries, `evictInactiveRooms(cutoff)` keyed on `lastActivityAt` + `isMember`.
- `database.dart`: register tables + DAO; `schemaVersion => 9`; migration `if (from < 9) { createTable(roomEntries); createTable(roomMemberEntries); createTable(roomKeyHistoryEntries); addColumn(outboundQueueEntries, itemType); }`.
- `storage_service.dart` + drift impl + **mock impl**: `saveRoom/getRoom/getRooms/updateRoomActivity/setRoomLastRead/saveRoomMember/setRoomMemberRemoved/getRoomMembers/setRoomKey/appendRoomKeyHistory/getRoomKeyHistory/evictInactiveRooms` + `enqueueTyped(target, blob, itemType)`. Then `dart run build_runner build`.

**Activity-based retention** (`retention.dart`): add `maxRoomIdleSeconds` + an `evictInactiveRooms` call. Policy: **never evict a room where `isMember=1`; evict only LEFT rooms idle past the window.** Second nuance: received `roomMessage` rows are `isOwn=0` and would be pruned by `evictOldEvents` at 30d — keep joined-room timelines durable by setting **`isSaved=1`** on room-message rows while joined (cleared on leave).

### 6. UI (reuse Plan 04a design system + comments widgets)

- `screens/voice/room_list_screen.dart` (modify): "recent calls" → **chatroom list** from `roomsProvider` (rooms where `isMember`); tile = name + last-message preview + unread dot + live-call indicator. FAB → create.
- `screens/voice/create_room_screen.dart` (modify): durable create — name + pick members from `mutualFollowsProvider` (no cap). On submit: mint key, author `roomCreate` + initial `roomMembership`, seal key + fan out to members.
- `screens/voice/room_screen.dart` (**new**): message list mirroring `widgets/comment_list.dart` (via `roomMessagesProvider(roomId)` → `getEventsByRef(roomId, kind: roomMessage)` with the comments allow-list/tombstone filter), composer mirroring `widgets/comment_input.dart`, `StarlingTopBar` (name + member count), call affordance ("Start call" / "Join call" when a `roomCallStarted` is live). On view → set `lastReadAt`.
- `providers/room_provider.dart` (**new**): `roomsProvider`, `roomMessagesProvider(roomId)`, `RoomMessageController`, `roomMembersProvider(roomId)`, `unreadRoomsCountProvider`.
- `shell/app_shell.dart` (modify): Rooms-tab unread badge (`badges:{...StarlingTab.rooms: unreadRoomsCountProvider}` — `StarlingBottomTabBar` already supports it).
- `router.dart` (modify): add nested `/voice/room/:roomId` (durable room screen); keep root-pinned `/voice/room` → `ActiveRoomScreen` for the live mesh.
- `service_providers.dart`: wire `RoomService` / `RoomMessageService`; gate behind new `kChatroomsEnabled` flag (`utils/feature_flags.dart`, mirrors `kVoiceEnabled`).

### 7. Relationship to Plan 16

Plan 17 **supersedes the local-only `voice_rooms` tables as the room-of-record** but does **not** delete the call machinery. The room list now shows chatrooms. `voice_rooms`/`voice_room_participants` are demoted to optional **per-call session logs** (their 7-day/createdAt retention is fine) with a **distinct call-session id**. `RoomManager`, `RoomSignaling`, `VoiceService`, `webrtc_voice_service`, `ice_config`, the invite sheet, and `CallOverlay` are reused unchanged — only a thin `startRoomCall` + 4-cap-on-accept are added.

## Phasing

- **A — Models & kinds:** `event_kind.dart` (+100-103), room content codecs, `kChatroomsEnabled`; `signAndEncryptForRoom` on `ContentKeyService`/`PairwiseContentKeyService`/mock.
- **B — Storage:** 3 tables, `rooms_dao`, schema v9, `outbound_queue.itemType`, interface + drift + mock, build_runner.
- **C — Room lifecycle:** `RoomService` (create/add/remove/leave; mint+seal key; author `roomCreate`/`roomMembership`) + `RoomKeyRotationService` (mirror `key_rotation_service.dart`).
- **D — Durable messaging:** typed `outbound_drain.dart`; `RoomMessageService`; `room_ingest.dart` + `events_push_handler` switch; **kind-exclusion isolation filter** in `events_handler.dart` + `manifest_handler.dart`.
- **E — Call integration:** `RoomManager.startRoomCall` + 4-cap-on-accept; distinct call-session id; durable `roomCallStarted`.
- **F — UI:** providers, list/create/room screens, badge, router, retention.
- **G — Verification:** the test matrix below.
- **H — (deferred, riskiest):** room-scoped pull convergence — `GET /room-events?room_id=` (membership-gated), a room-sync loop, store received room-event wire bytes for re-serve. Build storage to support it now (a `roomEncryptedPayload` column or reuse `encryptedPayload`); implement later. This is what makes large/partitioned rooms fully converge.

## Riskiest / least-clean spots

1. **Room-scoped convergence (H)** — the pull plane is per-author; a shared multi-author timeline needs a new endpoint + sync loop. v1 push-fanout + bounded replay is a pragmatic substitute, not full partition-healing.
2. **`SealedDeliveryChannel` does NOT fit room keys** — single-stream-per-recipient + two-slot ack. We bypass it for raw `sealDeliveryPayload` over the queue.
3. **`outbound_drain.dart` hardcodes `type:'event'`** — generalizing touches a hot retry path.
4. **Broadcast-serving leak** — kinds 100-103 must be excluded from `getOwnAndIncomingRefs`/`buildEventsEnvelope`/manifest, or room text leaks to followers under the feed key. Easy to miss, security-relevant.
5. **Plan 16 id conflation** — chatroom `roomId` vs ephemeral call-session id; conflation silently overwrites call history.
6. **Retention of received room messages** — `isOwn=0` rows prune at 30d; need `isSaved=1` immunity while joined.
7. **Unbounded membership × push-fanout** — O(members)/message delivery cost; large rooms need Phase H.
8. **Call glare** — simultaneous "start call" can form two meshes; v1 leans on RoomManager de-dup, no hard tiebreak.

## Verification

**Unit/integration (`flutter test`, mock loopback, Plan 16 style):**
- Multi-member convergence: 3 mock storages; A authors → fan-out to B & C → drain → ingest → both decrypt under room key → timelines equal; include an offline member that converges after reconnect (queue retry, no 4xx).
- Key seal/rotate: `sealDeliveryPayload`/unseal round-trip; remove member → rotate → removed member can't decrypt post-rotation but can decrypt archived-window messages; remaining members stay readable.
- Add-member history: add D → current key sealed + bounded replay → D reads prior history.
- **Isolation:** assert kinds 100-103 absent from `buildEventsEnvelope`/manifest output.
- **Privacy:** assert the text path emits no signaling/presence; presence frames emitted only by `startRoomCall`/accept.
- Call: `startRoomCall` fans `roomInvite` to all members; ≤4 admitted, 5th gets `reason:'full'`; `roomCallStarted` persisted.
- Retention: joined-room messages survive 30d; left+idle room evicted by `evictInactiveRooms`.
- Migration v8→v9: open a v8 db, migrate, assert 3 new tables + `outbound_queue.itemType`, existing rows intact.

**Manual, two devices:** create room + exchange text online and across an offline gap; add a 3rd member mid-stream (history replay); start a call from the room (both get the invite, audio over the Plan 16 mesh); remove a member and confirm key rotation cuts off their new-message visibility.

## Known limitations (v1)

1. Push-fanout only — no full multi-source pull convergence (Phase H); large/partitioned rooms may not fully heal.
2. Bounded history replay for new members (newest K), not full backfill.
3. Live-call cap 4; "call full" beyond that.
4. Creator-only admin; no member-initiated invites or multi-admin.
5. No push (project constraint) — live call ping reaches only members whose app is foregrounded/FG-alive; everyone else relies on the durable `roomCallStarted`.
6. No causal ordering; eventual consistency by `(createdAt, id)`.
7. Text only; media deferred.

## Critical files to read before implementing

- `lib/sync/outbound_drain.dart` — generalize hardcoded `type:'event'`; spine of delivery.
- `lib/server/handlers/events_push_handler.dart` — add `room-key`/`room-event` ingest (+ new `room_ingest.dart`).
- `lib/services/crypto/pairwise_content_key_service.dart` — add `signAndEncryptForRoom` (reuses `deriveMsgKey`/`encryptEvent`).
- `lib/services/storage/database.dart` — schema v8→v9, 3 tables, DAO, `outbound_queue.itemType`.
- `lib/server/handlers/events_handler.dart` + `manifest_handler.dart` — the broadcast-serving seams that MUST exclude kinds 100-103.
- `lib/services/crypto/key_rotation_service.dart` — pattern to mirror for room-key rotation.
- `lib/services/voice/room_manager.dart` — reused call engine; add `startRoomCall` + 4-cap-on-accept.
- `lib/services/comment_service.dart` + `lib/providers/comments_provider.dart` + `lib/widgets/comment_list.dart`/`comment_input.dart` — the authoring/read/UI template to mirror.
