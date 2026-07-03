//! Zero-knowledge guard: the relay's serving path must never link a
//! content-AEAD / feed-key decryption crate. The relay holds no feed keys
//! and must not even contain the machinery to use them.
//!
//! We walk the *normal* (non-dev) dependency closure of
//! `starling-relay-http` via `cargo tree` and fail if any denylisted crate
//! appears. Signature/hash crates (ed25519, blake2, sha2, curve25519) are
//! fine — they authenticate and address content, they don't decrypt it.
//! Tor's own AEAD usage lives behind `starling-arti`, which is NOT in this
//! crate's dependency subtree, so it is correctly out of scope here.

use std::process::Command;

/// Crate names that would mean a relay crate can decrypt feed content. AEAD
/// stream ciphers + high-level secretbox/box constructions + the whole
/// libsodium family. Signature/hash crates (ed25519, blake2, sha2,
/// curve25519) are intentionally NOT here — they authenticate and address
/// content, they don't decrypt it.
const DENYLIST: &[&str] = &[
    // ChaCha/Salsa AEAD constructions. NOTE: the *raw* `chacha20` /
    // `salsa20` stream ciphers are intentionally NOT here — they ship as
    // CSPRNG cores (e.g. `rand` → `uuid`) with no AEAD attached, so linking
    // one is not a decryption capability. The poly1305-carrying AEAD crates
    // below are.
    "chacha20poly1305",
    "xchacha20poly1305",
    "xsalsa20poly1305",
    // High-level constructions + the AEAD trait crate (anything wiring a
    // real AEAD pulls this).
    "crypto_box",
    "crypto_secretbox",
    "aead",
    // AES AEAD
    "aes-gcm",
    "aes-gcm-siv",
    // libsodium bindings + other full crypto libs
    "sodiumoxide",
    "libsodium-sys",
    "libsodium-sys-stable",
    "dryoc",
    "orion",
];

/// Every relay crate that ingests untrusted request bodies. All must stay
/// off the decryption denylist — the admin crate handles pairing/unpair
/// bodies and was previously unchecked (L4).
const GUARDED_CRATES: &[&str] = &["starling-relay-http", "starling-relay-admin", "starling-wire"];

fn deps_of(crate_name: &str) -> Vec<String> {
    let output = Command::new(env!("CARGO"))
        .args([
            "tree",
            "-p",
            crate_name,
            "--edges",
            "normal",
            "--prefix",
            "none",
            "--no-dedupe",
        ])
        .output()
        .expect("run cargo tree");
    assert!(
        output.status.success(),
        "cargo tree failed for {crate_name}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let tree = String::from_utf8_lossy(&output.stdout);
    tree.lines()
        // Lines look like "crate-name v1.2.3 (...)".
        .filter_map(|line| line.split_whitespace().next())
        .filter(|name| DENYLIST.contains(name))
        .map(|s| s.to_string())
        .collect()
}

#[test]
fn zero_knowledge_crates_link_no_content_decryption_crate() {
    let mut violations = Vec::new();
    for crate_name in GUARDED_CRATES {
        let offenders = deps_of(crate_name);
        if !offenders.is_empty() {
            violations.push(format!("{crate_name} → {offenders:?}"));
        }
    }
    assert!(
        violations.is_empty(),
        "zero-knowledge violation: {violations:?}"
    );
}
