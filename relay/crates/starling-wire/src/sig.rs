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
/// signature by `pubkey` over `blake2b256(body)`. This is the
/// `X-Starling-Sig` contract from `relay_push_service.dart`.
pub fn verify_owner_sig(pubkey: &[u8], body: &[u8], sig: &[u8]) -> bool {
    let digest = blake2b256(body);
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
}
