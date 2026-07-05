//! Zero-knowledge guard: the relay's serving path must never link a
//! content-AEAD / feed-key decryption crate. The relay holds no feed keys
//! and must not even contain the machinery to use them.
//!
//! We walk the *normal* (non-dev) dependency closure of each guarded crate
//! via `cargo tree` and fail if any denylisted crate appears. Signature/hash
//! crates (ed25519, blake2, sha2, curve25519) are fine — they authenticate
//! and address content, they don't decrypt it. Tor's own AEAD usage lives
//! behind `starling-arti`, which is NOT in these crates' dependency
//! subtrees, so it is correctly out of scope here.
//!
//! **Voice (Plan 20).** `starling-relay-voice` terminates DTLS-SRTP, which
//! legitimately requires AEAD crates — that is hop-by-hop *transport*
//! encryption the relay is designed to terminate; the audio inside stays
//! end-to-end encrypted by the clients (FrameCryptor), and the forwarder
//! never decodes or inspects it. So the voice crate cannot join the AEAD
//! denylist walk. Its zero-knowledge property is enforced three other ways:
//! 1. a codec denylist walk (no Opus/audio decode machinery anywhere in the
//!    shipped binary — see [`VOICE_DENYLIST`]),
//! 2. a boundary walk keeping the WebRTC stack out of the store-and-forward
//!    crates (so the AEAD walk stays meaningful), and
//! 3. the byte-identical forwarding loopback test in `starling-relay-voice`
//!    (no transcode path exists at runtime).

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

/// Crate names that would mean the relay can *decode* (not just forward)
/// audio. The SFU is a pure forwarder of FrameCryptor ciphertext; linking a
/// codec is the capability we must never gain. Checked over the voice crate
/// AND the shipped binary, so nothing else can smuggle one in either.
const VOICE_DENYLIST: &[&str] = &[
    // Opus (the only codec Starling voice uses on the wire)
    "opus",
    "audiopus",
    "audiopus_sys",
    "opus-sys",
    "libopus-sys",
    "magnum-opus",
    // General audio decode/processing stacks
    "symphonia",
    "dasp",
    "hound",
    "rubato",
    "samplerate",
    "fdk-aac",
    "webrtc-audio-processing",
];

/// Crates that must keep the WebRTC/SRTP stack OUT of their dependency
/// trees. If one of these ever depends on the voice crate (or str0m
/// directly), the AEAD walk above silently loses its meaning — this test
/// turns that into a loud failure instead.
const VOICE_BOUNDARY: &[&str] = &["starling-relay-voice", "str0m", "webrtc", "webrtc-rs"];

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
        .map(|s| s.to_string())
        .collect()
}

/// Exact name match, or a dash-separated family member ("symphonia" also
/// catches "symphonia-codec-…"; "webrtc" also catches "webrtc-srtp").
fn denied(name: &str, denylist: &[&str]) -> bool {
    denylist
        .iter()
        .any(|d| name == *d || name.strip_prefix(d).is_some_and(|rest| rest.starts_with('-')))
}

fn violations(crates: &[&str], denylist: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    for crate_name in crates {
        let offenders: Vec<String> = deps_of(crate_name)
            .into_iter()
            .filter(|name| denied(name, denylist))
            .collect();
        if !offenders.is_empty() {
            out.push(format!("{crate_name} → {offenders:?}"));
        }
    }
    out
}

#[test]
fn zero_knowledge_crates_link_no_content_decryption_crate() {
    let violations = violations(GUARDED_CRATES, DENYLIST);
    assert!(
        violations.is_empty(),
        "zero-knowledge violation: {violations:?}"
    );
}

/// The SFU (and the whole shipped binary) must not be able to decode audio:
/// forwarding FrameCryptor ciphertext is all it does, byte-identically.
#[test]
fn voice_path_links_no_audio_codec() {
    let violations = violations(&["starling-relay-voice", "starling-relay"], VOICE_DENYLIST);
    assert!(
        violations.is_empty(),
        "audio-decode capability violation: {violations:?}"
    );
}

/// The store-and-forward crates must not grow a dependency on the WebRTC
/// stack — that would put AEAD crates in their trees "legitimately" and gut
/// the zero-knowledge walk above.
#[test]
fn webrtc_stack_stays_out_of_store_and_forward_crates() {
    let violations = violations(GUARDED_CRATES, VOICE_BOUNDARY);
    assert!(
        violations.is_empty(),
        "voice/WebRTC boundary violation: {violations:?}"
    );
}
