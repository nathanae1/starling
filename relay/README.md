# Starling headless relay

An optional, self-hostable, always-on **store-and-forward** service for
Starling. It caches an Owner's *encrypted* events and media and serves them
to Followers over Tor when the Owner's phone is offline. It never decrypts
anything (zero-knowledge) and never proxies or aggregates across Owners.

It is the "standalone tier" of Starling's self-hosting gradient
(phone↔phone → old phone → standalone relay). See
[`app/plans/15-headless-relay.md`](../app/plans/15-headless-relay.md).

## Architecture (R3)

A single Rust process embeds [Arti](https://gitlab.torproject.org/tpo/core/arti)
and hosts N Tor onion services on one `TorClient`:

- one **admin onion** serving only `POST /pair`,
- one **per-Owner onion** (its own HS keypair) serving that Owner's
  read/write endpoints, reverse-proxied to a private loopback port.

Each Owner's Connection Card lists both the phone's onion and the relay's
onion. Followers prefer a phone↔phone path (LAN, libp2p-direct, then the
Owner's own onion) whenever one is reachable and fall back to the relay's
onion only when the phone is asleep/offline. No shared keys, no
OnionBalance, no C-tor, no supervisord.

## Crates

| Crate | Responsibility |
|-------|----------------|
| `starling-arti` | Shared Tor core (TorClient + N onion services). Also consumed by the phone FFI bridge. |
| `starling-wire` | CBOR wire types + Ed25519/BLAKE2b verification. Zero-knowledge (no decrypt deps). |
| `starling-relay-storage` | SQLite (paired owners, pending pairings, served events + media). |
| `starling-relay-http` | Per-Owner Follower-facing reads + Owner-signed push. |
| `starling-relay-admin` | Admin web UI + onion-facing `/pair` handler. |
| `starling-relay` | The binary: config, Arti, supervisor, CLI. |

## Endpoints

Per-Owner onion (read = no auth; write = `X-Starling-Pubkey` +
`X-Starling-Sig`):

- `GET  /status` — JSON `{pubkey, version, event_count, media_storage_used}`
- `GET  /manifest?since=&until=` — CBOR `{pubkey, events:[{id,created_at}], has_older}`
- `GET  /events?since=` — CBOR Envelope of stored EncryptedEvents
- `GET  /media/<hash>` — raw encrypted blob
- `POST /events` — Owner pushes `{items:[{id,payload}]}`
- `POST /media/<hash>` — Owner pushes a raw blob

Admin onion: `POST /pair` only.

> **v1 limitation:** the relay omits the `/manifest` `new_feed_key` field —
> it holds no per-Follower key-distribution state. A Follower that needs a
> feed-key rotation must reach the phone.

## Build & test

```sh
cd relay
cargo test --workspace          # 23 tests; network-Tor tests are #[ignore]'d
cargo build --release -p starling-relay
```

Run the onion-boot smoke test (needs live Tor, ~30s):

```sh
cargo test -p starling-arti --test onion_boot -- --ignored --nocapture
```

## Run

```sh
# create the DB + dirs
starling-relay migrate --config config.toml
# run it
starling-relay serve --config config.toml
# in another shell, mint a pairing QR (prints to terminal)
starling-relay pair --config config.toml --label my-phone
```

The admin UI is on `127.0.0.1:8088` by default. Reach it over SSH
(`ssh -L 8088:127.0.0.1:8088 user@host`). To bind it to a LAN address, set a
password first: `starling-relay set-password --config config.toml`.

## Deploy

- **Docker:** `docker build -f relay/docker/Dockerfile -t starling-relay .`
  The container runs as uid 65532 (`nonroot`); named volumes work out of the
  box, but a bind-mounted data dir must be `chown -R 65532:65532` on the host.
  The admin UI defaults to loopback *inside the container* (unreachable from
  the host). To use it, opt in explicitly — set a password first, then bind
  it and publish the port to the host's loopback only:

  ```sh
  docker run --rm -it -v relay-data:/var/lib/starling-relay starling-relay set-password
  docker run -d -v relay-data:/var/lib/starling-relay \
    -e STARLING_RELAY_BIND_ADMIN=0.0.0.0:8088 \
    -p 127.0.0.1:8088:8088 starling-relay
  ```

  (`0.0.0.0` inside the container is required for Docker port-forwarding;
  the `-p 127.0.0.1:` prefix keeps it off the LAN. The relay logs a warning
  at boot if the admin UI is bound non-loopback with no password set.)
- **systemd/Debian:** `relay/scripts/install-debian.sh`
- **Proxmox LXC:** `relay/scripts/proxmox-install.sh <ctid> <binary>`
- **CI/releases:** `.github/workflows/relay.yml` (tag `relay-v*`)
