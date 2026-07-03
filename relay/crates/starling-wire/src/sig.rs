//! BLAKE2b-256 + Ed25519, matching the phone's libsodium usage.
//!
//! - `blake2b256` == libsodium `crypto_generichash` with `outLen = 32`
//!   (unkeyed BLAKE2b-256).
//! - Owner signatures == libsodium `crypto_sign_detached` (standard
//!   Ed25519) over `blake2b256(body)`.

use blake2::digest::consts::U32;
use blake2::{Blake2b, Digest};
use ed25519_dalek::{Signature, VerifyingKey};

/// BLAKE2b with a 32-byte digest (unkeyed).
pub fn blake2b256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(data);
    let out = hasher.finalize();
    let mut digest = [0u8; 32];
    digest.copy_from_slice(&out);
    digest
}

/// Verify a standard Ed25519 signature over `msg`. `pubkey` must be 32
/// bytes, `sig` 64 bytes; any other length returns `false`.
pub fn verify_ed25519(pubkey: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    let pk: [u8; 32] = match pubkey.try_into() {
        Ok(v) => v,
        Err(_) => return false,
    };
    let verifying_key = match VerifyingKey::from_bytes(&pk) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let sig_bytes: [u8; 64] = match sig.try_into() {
        Ok(v) => v,
        Err(_) => return false,
    };
    let signature = Signature::from_bytes(&sig_bytes);
    verifying_key.verify_strict(msg, &signature).is_ok()
}

/// Verify an Owner write signature: `sig` must be a valid Ed25519
/// signature by `pubkey` over `blake2b256(body)`. This is the legacy
/// `X-Starling-Sig` contract (body-only — no request binding); kept so
/// phones and self-hosted relays can update out of step. New clients send
/// the bound scheme below.
pub fn verify_owner_sig(pubkey: &[u8], body: &[u8], sig: &[u8]) -> bool {
    let digest = blake2b256(body);
    verify_ed25519(pubkey, &digest, sig)
}

/// Domain tag for the request-bound Owner signature scheme.
pub const OWNER_REQ_DOMAIN: &[u8] = b"starling-owner-req-v1";

/// Digest for the request-bound Owner signature:
/// `blake2b256(domain ‖ method ‖ path ‖ u64_be(unix_ts) ‖ blake2b256(body))`.
///
/// Binding method+path+timestamp closes the replay hole in the body-only
/// scheme (a captured GET signature was valid forever, on every relay the
/// Owner ever paired with). Concatenation is unambiguous without length
/// prefixes: the domain is constant, HTTP methods never contain `/`, the
/// path always starts with `/`, and the trailing fields are fixed-width.
/// Mirrors `relay_push_service.dart`.
pub fn owner_request_digest(method: &str, path: &str, unix_ts: i64, body: &[u8]) -> [u8; 32] {
    let mut buf = Vec::with_capacity(
        OWNER_REQ_DOMAIN.len() + method.len() + path.len() + 8 + 32,
    );
    buf.extend_from_slice(OWNER_REQ_DOMAIN);
    buf.extend_from_slice(method.as_bytes());
    buf.extend_from_slice(path.as_bytes());
    buf.extend_from_slice(&(unix_ts as u64).to_be_bytes());
    buf.extend_from_slice(&blake2b256(body));
    blake2b256(&buf)
}

/// Verify a request-bound Owner signature (the `X-Starling-Ts` scheme).
pub fn verify_owner_request_sig(
    pubkey: &[u8],
    method: &str,
    path: &str,
    unix_ts: i64,
    body: &[u8],
    sig: &[u8],
) -> bool {
    let digest = owner_request_digest(method, path, unix_ts, body);
    verify_ed25519(pubkey, &digest, sig)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    #[test]
    fn owner_sig_roundtrip() {
        let sk = SigningKey::from_bytes(&[42u8; 32]);
        let pk = sk.verifying_key();
        let body = b"some cbor request body";
        let digest = blake2b256(body);
        let sig = sk.sign(&digest);
        assert!(verify_owner_sig(
            pk.as_bytes(),
            body,
            &sig.to_bytes()
        ));
        // Tamper the body → reject.
        assert!(!verify_owner_sig(
            pk.as_bytes(),
            b"different body",
            &sig.to_bytes()
        ));
    }

    #[test]
    fn wrong_length_rejected() {
        assert!(!verify_ed25519(&[0u8; 31], b"x", &[0u8; 64]));
        assert!(!verify_ed25519(&[0u8; 32], b"x", &[0u8; 63]));
    }

    #[test]
    fn bound_request_sig_binds_every_field() {
        let sk = SigningKey::from_bytes(&[7u8; 32]);
        let pk = sk.verifying_key();
        let body = b"cbor body";
        let digest = owner_request_digest("POST", "/events", 1_750_000_000, body);
        let sig = sk.sign(&digest).to_bytes();

        let ok = |m: &str, p: &str, t: i64, b: &[u8]| {
            verify_owner_request_sig(pk.as_bytes(), m, p, t, b, &sig)
        };
        assert!(ok("POST", "/events", 1_750_000_000, body));
        assert!(!ok("GET", "/events", 1_750_000_000, body)); // method bound
        assert!(!ok("POST", "/media-manifest", 1_750_000_000, body)); // path bound
        assert!(!ok("POST", "/events", 1_750_000_001, body)); // ts bound
        assert!(!ok("POST", "/events", 1_750_000_000, b"other")); // body bound
        // The bound digest is NOT valid under the legacy body-only scheme.
        assert!(!verify_owner_sig(pk.as_bytes(), body, &sig));
    }
}
