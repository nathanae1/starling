//! Owner-signature verification for write endpoints.
//!
//! Matches `server/middleware/owner_signature_middleware.dart`:
//! `X-Starling-Pubkey: base64(raw 32-byte pubkey)` and
//! `X-Starling-Sig: base64(Ed25519.sign(sk, blake2b256(body)))`. 401 on a
//! missing/malformed/invalid signature, 403 when the pubkey is valid but
//! isn't this router's Owner.

use axum::http::{HeaderMap, StatusCode};
use base64::Engine;

/// Verify the Owner signature over `body`. Returns `Ok(())` or an
/// `(status, message)` to turn into a response.
pub fn verify_owner_request(
    headers: &HeaderMap,
    body: &[u8],
    owner_pubkey: &[u8; 32],
) -> Result<(), (StatusCode, &'static str)> {
    let pubkey_b64 = headers
        .get("x-starling-pubkey")
        .and_then(|v| v.to_str().ok())
        .ok_or((StatusCode::UNAUTHORIZED, "missing x-starling-pubkey"))?;
    let sig_b64 = headers
        .get("x-starling-sig")
        .and_then(|v| v.to_str().ok())
        .ok_or((StatusCode::UNAUTHORIZED, "missing x-starling-sig"))?;

    let engine = base64::engine::general_purpose::STANDARD;
    let pubkey = engine
        .decode(pubkey_b64)
        .map_err(|_| (StatusCode::UNAUTHORIZED, "bad x-starling-pubkey base64"))?;
    let sig = engine
        .decode(sig_b64)
        .map_err(|_| (StatusCode::UNAUTHORIZED, "bad x-starling-sig base64"))?;

    if !starling_wire::verify_owner_sig(&pubkey, body, &sig) {
        return Err((StatusCode::UNAUTHORIZED, "invalid signature"));
    }
    // Valid signature, but is it THIS Owner? Mismatch → 403.
    if pubkey.as_slice() != owner_pubkey.as_slice() {
        return Err((StatusCode::FORBIDDEN, "pubkey is not this relay owner"));
    }
    Ok(())
}
