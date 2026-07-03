# Ubiquitous Language

## Identity & people

| Term                | Definition                                                                                     | Aliases to avoid                       |
| ------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------- |
| **Identity**        | An Ed25519 keypair generated on device that represents a person in Starling.                      | Account, user, login                   |
| **Pubkey**          | The public half of an Identity; the addressable name of a person in the network.               | User ID, handle, username              |
| **Profile**         | Display name, bio, and avatar for an Identity, stored as a signed kind=2 Event.                | User info, bio data                    |
| **Recovery phrase** | A 24-word BIP-39 mnemonic that re-derives an Identity keypair.                                 | Seed phrase, mnemonic, backup phrase   |
| **Friend**          | Someone you follow in the UI — the user-facing word for a Follow.                              | Contact, buddy                         |
| **Follow**          | The stored relationship that grants you a peer's Feed key and connection endpoints.            | Subscription, connection               |
| **Follower**        | Someone who follows your Identity; holds your current Feed key.                                | Subscriber                             |
| **Peer**            | Any Starling device reachable by your device — not necessarily a Friend.                          | Node, host                             |

## Content & events

| Term                | Definition                                                                                            | Aliases to avoid                           |
| ------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| **Event**           | The base record type — signed, then encrypted, for all user content.                                  | Message, record, object                    |
| **Post**            | A kind=1 Event containing a caption and one photo.                                                    | Photo, update, entry                       |
| **Comment**         | A kind=4 Event whose `ref` points at a target Post.                                                   | Reply, response                            |
| **Like**            | A kind=5 Event whose `ref` points at a target Post; toggled by a kind=6 Delete.                       | Reaction, heart, favorite                  |
| **Delete**          | A kind=6 Event whose `ref` points at the Event being tombstoned.                                      | Remove, tombstone (internal-only)          |
| **MediaRef**        | `{ hash, mime_type, size }` reference inside an Event pointing to a Media blob.                       | Attachment, asset, media pointer           |
| **Media**           | An encrypted photo blob stored on disk and addressed by the BLAKE2b-256 hash of its plaintext.        | File, image, attachment                    |
| **Event kind**      | An open integer enum on Event that identifies its type; unknown kinds are stored and synced anyway.   | Type, event type                           |
| **Extensions**      | A `Map<string, bytes>` on Events and EnvelopeItems; on Events it is inside the signature.             | Metadata, extra fields                     |
| **Save**            | A local-only flag (`is_saved`) that exempts an Event from retention eviction; produces no Event.      | Bookmark, favorite, pin, star              |

## Encryption & keys

| Term               | Definition                                                                                               | Aliases to avoid                         |
| ------------------ | -------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| **Identity key**   | The Ed25519 keypair for signing Events and deriving pairwise keys.                                       | Master key, signing key                  |
| **Feed key**       | The symmetric XChaCha20-Poly1305 key used to encrypt an Identity's Events; shared with each Follower.    | Group key, content key, secret           |
| **Epoch**          | A monotonic counter on the Feed key ratchet; each Event is encrypted with that epoch's key.              | Generation, version                      |
| **Epoch key**      | The Feed key at a specific epoch, derived via BLAKE2b hash ratchet from the previous epoch.              | Sub-key, round key                       |
| **Ratchet**        | The one-way advancement of Feed key from epoch N to N+1 that gives forward secrecy for new Followers.    | Rotation (reserved — see Key rotation)   |
| **Key rotation**   | Generating a brand-new random Feed key on Follower removal, breaking the ratchet chain.                  | Re-key, refresh                          |
| **Pairwise key**   | An XChaCha20-Poly1305 key derived by X25519 DH + KDF between two Identities, used for 1:1 encryption.    | Shared key, dyad key                     |
| **Audience**       | The abstraction that chooses which keys encrypt an Event; v1 has one variant: `broadcast`.               | Scope, recipient set                     |

## Transport & sync

| Term                   | Definition                                                                                                     | Aliases to avoid                                |
| ---------------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| **EncryptedEvent**     | The ciphertext record `{ pubkey, created_at, epoch, nonce, payload }` that carries a serialized Event.         | Sealed event, ciphertext event                  |
| **Envelope**           | The **untrusted** transport container of typed EnvelopeItems moved by every sync or push.                      | Packet, message, batch                          |
| **EnvelopeItem**       | A typed payload inside an Envelope; each item type defines its own integrity mechanism.                        | Entry, record, part                             |
| **Manifest**           | The lightweight list `{ events: [{id, created_at}] }` returned by `/manifest` for sync diffing.                | Index, catalog, toc                             |
| **Sync**               | The full exchange cycle: want-list → Manifest diff → fetch missing Events → decrypt + verify → store.          | Refresh, poll, pull                             |
| **Backfill**           | Explicit user-triggered fetch of Events older than the 30-day sync window.                                     | Load more, history fetch                        |
| **Sync window**        | The 30-day lookback that bounds automatic syncing; older content is only pulled via Backfill.                  | Retention window (reserved — see Retention)     |
| **Outbound queue**     | Local queue of signed Events destined for a specific target Pubkey on next Sync.                               | Pending events, outbox                          |
| **Connection card**    | `{ pubkey, endpoints, capabilities }` encoded as CBOR→base64url and carried in QR codes and Invite links.      | Card, contact, business card                    |
| **Invite link**        | A `starling://connect?card={base64url}` URL that embeds a Connection card.                                        | Share link, follow link                         |
| **Follow request**    | A `POST /follow-request` containing an encrypted Connection card from a would-be Follower.                     | Add request, friend request                     |
| **Follow accept**     | The Owner's reply that sends an encrypted Feed key back to the requesting Pubkey.                              | Approval, acceptance                            |

## Network & infrastructure

| Term                     | Definition                                                                                                | Aliases to avoid                               |
| ------------------------ | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| **On-device server**     | The shelf HTTP server running inside the Starling app that serves its Owner's Events and Media.              | Local server, embedded server, node server     |
| **Onion service**        | An Arti-managed Tor hidden service whose `.onion` address appears in the Connection card.                 | Hidden service, Tor service                    |
| **Relay**                | An optional zero-knowledge store-and-forward service that caches and serves paired Owners' encrypted content 24/7. Multi-owner: one relay hosts many Owners, partitioned per Pubkey, each on its own `.onion`. | Server, backend, host                          |
| **Standalone relay**     | The headless Rust binary Relay for a Linux box (Proxmox LXC, Raspberry Pi, VPS, NAS). The only shipped Relay deployment; the earlier spare-device phone Relay was abandoned. | Server relay, self-hosted relay                |
| **LAN tier**             | mDNS-discovered peers on the same Wi-Fi — the fastest, zero-config Sync path.                             | Local network                                  |
| **Tor tier**             | WAN-reachability path via Arti and Onion services; used when LAN and Relay are unavailable.               | Onion path                                     |
| **Hole-punch**           | A STUN-assisted attempt to upgrade a Tor-signaled link to a direct WAN socket for lower latency.          | NAT traversal, direct connect                  |
| **Signaling channel**    | The WebSocket-on-shelf path carrying pairwise-encrypted ephemeral Events (e.g. Voice room negotiation).   | Socket, control channel                        |
| **Voice room**           | An ephemeral invite-only WebRTC audio call between mutual Follows; not a persistent feed Event.           | Call, group call, audio room                   |
| **Retention**            | The local eviction policy — 30-day default plus LRU grace — that bounds storage of others' content.       | Expiry, cleanup, pruning                       |

## Relationships

- An **Identity** owns exactly one current **Feed key**, plus zero or more historical ones after **Key rotation**.
- An **Event** is signed by one **Identity key**, then encrypted with one **Epoch key** of that Identity's **Feed key**.
- A **Post** is an **Event** of kind=1; **Comments** and **Likes** are **Events** whose `ref` points at a **Post**.
- A **MediaRef** lives inside an **Event**; the corresponding **Media** blob is encrypted separately with the same **Epoch key**.
- Every transport carries **Envelopes**, which contain one or more **EnvelopeItems** — not bare **EncryptedEvents**.
- A **Follow** stores the target's **Connection card** and the **Feed key** they shared during **Follow accept**.
- **Unfollowing** a **Follower** triggers **Key rotation** — not **Ratchet** advancement.
- A **Relay** hosts one or more **Identities**, each partitioned by **Pubkey** and reachable on its own relay-issued **Onion service**; the **Standalone relay** is the only shipped deployment.
- **Save** affects local **Retention** only — it produces no **Event** and is never synced.

## Example dialogue

> **Dev:** "When Alice unfollows Bob, do we **Ratchet** the **Feed key**?"

> **Domain expert:** "No — **Ratchet** is the forward-only hash chain we use to advance **Epochs** for new **Followers**. Removing a **Follower** triggers a **Key rotation**: a brand-new random **Feed key**, not derived from the chain. Bob has all the old **Epoch keys**, so ratcheting wouldn't lock him out."

> **Dev:** "Got it. And the new **Feed key** reaches Carol how?"

> **Domain expert:** "It rides on Carol's next **Sync**. Alice's **On-device server** tucks the encrypted key into the **Manifest** response. Carol decrypts with the **Pairwise key** she shares with Alice and updates her **Follow** row."

> **Dev:** "If Carol **Saves** one of Alice's old **Posts**, does anything sync back?"

> **Domain expert:** "Nothing. **Save** is a local **Retention** flag, not an **Event kind**. It exempts the **Post** and its **Media** from eviction, but Alice never learns. If we ever want social signals for saves, that's a new **Event kind** with its own design — don't retrofit it."

> **Dev:** "Last one — two **Friends** on mobile data can't establish a **Hole-punch**. What happens?"

> **Domain expert:** "They fall back to the **Tor tier** for **Sync**, which is fine — it's 3-5s per request and the feed is async. For **Voice rooms** that's too slow, so the call just fails with an honest error. A **Spare-device relay** on either side fixes both cases because the **Relay** sits on an Onion service that's always reachable."

## Flagged ambiguities

- **"Friend" vs "Follow" vs "Follower"** — three words, three distinct meanings. **Friend** is the user-facing label in UI copy ("Friends" tab). **Follow** is the local DB row representing someone *you* follow. **Follower** is someone who follows *you*. Don't use them interchangeably in code or specs; the app-spec and plans already conflate these in a couple of places.
- **"Rotation" vs "Ratchet"** — both advance the **Feed key**, but **Ratchet** is the deterministic hash chain for forward secrecy toward new **Followers**, while **Key rotation** is a random re-key that breaks the chain after **Follower** removal. Never say "rotate the epoch" — say "advance the epoch" (Ratchet) or "rotate the feed key" (Key rotation).
- **"Relay"** — used for three related concepts: (1) the role, (2) the **Spare-device relay** deployment, (3) the **Standalone relay** Rust binary. Default to the bare word for the role; qualify when the deployment matters.
- **"Save" vs "Bookmark"** — the plans use both. **Save** is the canonical action and DB column (`is_saved`); **bookmark** is reserved for the icon/affordance name. Don't introduce "favorite" or "pin".
- **"Recovery phrase" vs "seed phrase"** — protocol spec is explicit: the user-facing term is **Recovery phrase**. "Seed phrase" must not appear in UI, copy, logs, or docs.
- **"Reaction" vs "Like"** — plan 10 is titled "Comments, Reactions & Save" but MVP scope is just the heart. The canonical term is **Like** (kind=5). Reserve "reaction" for a hypothetical future with multiple emoji kinds.
- **"Event" vs "Post"** — every **Post** is an **Event**, but not every **Event** is a **Post** (profiles, comments, likes, deletes, room-lifecycle events are all Events). Don't say "post" when you mean any Event.
- **"Envelope" vs "EncryptedEvent"** — transports move **Envelopes**, not bare **EncryptedEvents**. The Envelope is untrusted; integrity is per-**EnvelopeItem**. Saying "we send the encrypted event" glosses over the trust model.
