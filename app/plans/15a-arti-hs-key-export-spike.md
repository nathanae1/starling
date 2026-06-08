# Plan 15a — Spike: Arti 0.34 HS identity-key export

Risk gate for Plan 15. Question: can the phone hand its onion-service Ed25519
identity key (the 64-byte expanded secret key) to the Linux relay so both
sides answer for the same `.onion` under OnionBalance v3?

**Answer: yes, cleanly, but the recommended approach is NOT to "export" a
key Arti generated. It is to generate the key ourselves and import it into
Arti at HS-launch.**

## The Arti 0.34 API surface, established

| Item | Crate / path | Public? |
|---|---|---|
| `HsIdKeypair` (the HS identity keypair wrapper) | `tor_hscrypto::pk::HsIdKeypair` | ✅ pub |
| `HsIdKeypair: AsRef<ExpandedKeypair>` | same | ✅ pub |
| `HsIdKeypair: ToEncodableKey` (`Key = ExpandedKeypair`) | same | ✅ pub |
| `HsIdKeypair: From<ExpandedKeypair>` | same | ✅ pub |
| `ExpandedKeypair::to_secret_key_bytes(&self) -> [u8; 64]` | `tor_llcrypto::pk::ed25519` | ✅ pub |
| `ExpandedKeypair::from_secret_key_bytes(bytes: [u8; 64]) -> Option<Self>` | same | ✅ pub |
| `HsIdKeypairSpecifier::new(nickname: HsNickname)` | `tor_hsservice::HsIdKeypairSpecifier` | ✅ pub |
| `KeyMgr::get<K: ToEncodableKey>(&dyn KeySpecifier) -> Result<Option<K>>` | `tor_keymgr::KeyMgr` | ✅ pub |
| `TorClient::launch_onion_service_with_hsid(config, HsIdKeypair) -> Result<...>` | `arti_client::TorClient` | ✅ pub |
| `TorClient::keymgr() / key_manager()` | — | ❌ **does not exist** |

The last row is the constraint that decides the design. `TorClient` does not
hand out a `KeyMgr`, so a post-hoc "get the key out of Arti's keystore"
flow would have to either (a) build a parallel `KeyMgr` against the same
on-disk keystore config, or (b) parse Arti's OpenSSH-formatted
`.expanded_ed25519_private` file directly. Both are fragile across Arti
upgrades. We don't have to do either.

## Recommended path: phone generates, then imports

```
At first launch:
  1. Generate ExpandedKeypair via tor_llcrypto::pk::ed25519
     (or via libsodium on the Dart side and bring 64 bytes across FFI —
     either works; staying inside Rust avoids re-validating libsodium's
     expanded-key derivation).
  2. Call expanded.to_secret_key_bytes() → [u8; 64].
  3. Persist those 64 bytes via flutter_secure_storage under a stable key
     ("arti.hs.starling.expanded_sk"). This is the canonical phone-side
     home for the HS secret key.
  4. Build HsIdKeypair::from(expanded), call
     TorClient::launch_onion_service_with_hsid(svc_cfg, hsid_kp).
     Arti's KeyMgr persists it under its own keystore on first launch.

On subsequent launches:
  1. Read 64 bytes from flutter_secure_storage.
  2. ExpandedKeypair::from_secret_key_bytes(bytes)?
  3. launch_onion_service_with_hsid(...) — Arti recognises the key, no
     overwrite of any existing keystore entry. (If Arti has cached a key
     under the same nickname, the docs say this call errors rather than
     overwriting; we handle by reading the cached one on disk via a
     pre-flight, or by calling launch_onion_service first time and
     skipping the with_hsid variant when our secret-storage entry is
     absent. Simpler: always own the key from day one.)

At pairing-with-relay time (Plan 15 §"Pairing flow"):
  1. Read 64 bytes from flutter_secure_storage.
  2. Derive wrap_key = HKDF-SHA512(token, "starling-relay-pair-v1", info).
  3. XChaCha20-Poly1305 wrap → wrapped_hs_key.
  4. POST to relay /pair.
```

## Relay-side import (informational — not part of this spike)

The relay runs C-tor, not Arti. Its on-disk format for a v3 HS identity key
is:

```
File: ${KeysDir}/hs_ed25519_secret_key   (mode 0600, owned by tor user)
Bytes:
  [0..32)   b"== ed25519v1-secret: type0 ==\x00\x00\x00"
  [32..96)  the 64-byte expanded secret key (same bytes we wrapped above)
```

So the relay's `/pair` handler does:
```rust
let mut f = std::fs::File::create(path)?;
f.write_all(b"== ed25519v1-secret: type0 ==\x00\x00\x00")?;
f.write_all(&unwrapped_64_bytes)?;
// chmod 0600, chown to the tor user
```

No Arti involvement on the relay. The `starling-arti` workspace crate
(Plan 15 §"Crate / process layout") does not need an `import_hs_key()`
helper for the relay — it only needs `export_hs_key()` / generation
helpers for the phone-side bridge. Plan 15 §"Reusable Rust" wording can
be tightened to reflect this.

## Plan 15 changes implied

- §"Risks / open questions" — strike the "may only support import, not
  export" hedge. The chosen design sidesteps the export question.
- §"Phone-side changes" → bullet on `arti_tor_service.dart` — replace
  `exportHsSecretKey()` shim semantics with `getHsSecretKey()`: the bytes
  live in `flutter_secure_storage`; the Rust side is consulted only at
  first generation.
- §"Critical files" → add `app/starling/lib/services/secure_storage/`
  (canonical location) for the new secure-storage key namespace.
- §"Reusable Rust" — `starling-arti`'s only new helper is
  `generate_hs_keypair() -> [u8; 64]` (a thin shim over
  `ExpandedKeypair::generate` + `to_secret_key_bytes`). Drop "import
  helper" — Arti's existing `launch_onion_service_with_hsid` already is
  that helper.
- Current `arti/inner.rs::create_onion_service` (line 140-198) — call
  site changes from `launch_onion_service(svc_cfg)` to
  `launch_onion_service_with_hsid(svc_cfg, hsid_kp)`. The keypair comes
  in as a new arg from the FFI layer.

## Migration note

Project is pre-launch; no installed clients have a persisted Arti-generated
HS key worth preserving. We switch to the generate-then-import flow with
no migration code. First app launch after this change rotates everyone's
`.onion` once; from then on it is stable and exportable.

## Verification checklist (next step, before Plan 15 code)

1. Add a `tor_llcrypto` dep to `starling_bridge/Cargo.toml` (or confirm
   it's already in the dep tree via `tor-hscrypto`'s public re-exports).
2. Write a 30-line standalone bin in `starling_bridge` that:
   a. Generates `ExpandedKeypair`, prints the 64 bytes hex,
   b. Reconstructs from bytes, calls
      `TorClient::launch_onion_service_with_hsid` against a temp
      `state_dir`,
   c. Reads back the `.onion` address Arti publishes,
   d. Asserts the address matches what we'd derive from the public-key
      half of our generated keypair.
3. If (d) passes: ship Plan 15 phone-side using this flow.
4. If (d) fails: that means our externally-generated key isn't being
   honored. Re-open the question; the fallback is the file-scrape path,
   not worth designing now.

This spike is research-only — no code committed. Next call is the
verification checklist above, then the Plan 15 phone-side §"Pairing flow"
implementation.
