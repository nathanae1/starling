//! Wire types + signature verification shared by the Starling phone and
//! the headless relay.
//!
//! **Zero-knowledge boundary.** This crate decodes the cleartext *headers*
//! of encrypted payloads and verifies Owner signatures. It contains no
//! feed-key, content-key, or decryption logic and must never gain a
//! dependency that does (enforced by `starling-relay-http`'s
//! `zero_knowledge` test).
//!
//! Every encoding here mirrors the phone's Dart wire format byte-for-byte
//! (CBOR via `package:cbor`, Crockford base32 for pubkey/id text,
//! BLAKE2b-256 + Ed25519 for auth). See the relevant Dart sources:
//! `models/{envelope,encrypted_event}.dart`,
//! `services/crypto/crockford_base32.dart`,
//! `services/{relay_push_service,relay_pairing_initiator}.dart`.

pub mod base32;
pub mod delete;
pub mod envelope;
pub mod event_header;
pub mod manifest;
pub mod pairing;
pub mod push;
pub mod sig;

/// Starling protocol version string (`kStarlingProtocolVersion`). Stamped
/// into the `version` field of every `/events` Envelope and `/status`.
pub const PROTOCOL_VERSION: &str = "2026-04-28";

pub use base32::{crockford_base32_decode, crockford_base32_encode};
pub use sig::{
    blake2b256, owner_request_digest, verify_ed25519, verify_owner_request_sig,
    verify_owner_sig,
};

/// Current unix time in seconds. Shared by every relay crate (timestamps in
/// wire payloads, token expiry, DB rows).
pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
