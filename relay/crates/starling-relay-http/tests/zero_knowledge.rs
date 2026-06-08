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

/// Crate names that would mean the serving path can decrypt feed content.
const DENYLIST: &[&str] = &[
    "chacha20poly1305",
    "xchacha20poly1305",
    "salsa20",
    "xsalsa20poly1305",
    "crypto_box",
    "crypto_secretbox",
    "sodiumoxide",
    "libsodium-sys",
    "aes-gcm",
];

#[test]
fn serving_path_links_no_content_decryption_crate() {
    let output = Command::new(env!("CARGO"))
        .args([
            "tree",
            "-p",
            "starling-relay-http",
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
        "cargo tree failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let tree = String::from_utf8_lossy(&output.stdout);

    let mut offenders = Vec::new();
    for line in tree.lines() {
        // Lines look like "crate-name v1.2.3 (...)".
        let name = line.split_whitespace().next().unwrap_or("");
        if DENYLIST.contains(&name) {
            offenders.push(name.to_string());
        }
    }
    assert!(
        offenders.is_empty(),
        "zero-knowledge violation: serving path links decryption crate(s): {offenders:?}"
    );
}
