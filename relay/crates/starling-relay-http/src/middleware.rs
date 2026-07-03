//! Owner-signature verification for write endpoints.
//!
//! Matches the phone's `services/relay_push_service.dart` `_signHeaders`:
//! `X-Starling-Pubkey: base64(raw 32-byte pubkey)` plus either
//!
//! - **bound scheme** (current): `X-Starling-Ts: <unix secs>` and
//!   `X-Starling-Sig: base64(Ed25519.sign(sk, owner_request_digest(method,
//!   path, ts, body)))` — binds method, path, and time so a captured
//!   signature can't be replayed against another route or forever;
//! - **legacy scheme** (no `X-Starling-Ts`): sig over `blake2b256(body)`.
//!   Accepted for one release so phones and self-hosted relays can update
//!   out of step.
//!
//! 401 on a missing/malformed/invalid/stale signature, 403 when the pubkey
//! is valid but isn't this router's Owner.

use axum::http::{HeaderMap, StatusCode};
use base64::Engine;

/// Max accepted `|now - X-Starling-Ts|`. Generous because requests ride
/// Tor and phone clocks drift.
const MAX_TS_SKEW_SECS: i64 = 600;

/// Verify the Owner signature over this request. Returns `Ok(())` or an
/// `(status, message)` to turn into a response.
pub fn verify_owner_request(
    headers: &HeaderMap,
    method: &str,
    path: &str,
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

    let valid = match headers.get("x-starling-ts") {
        Some(ts_header) => {
            let ts: i64 = ts_header
                .to_str()
                .ok()
                .and_then(|v| v.parse().ok())
                .ok_or((StatusCode::UNAUTHORIZED, "bad x-starling-ts"))?;
            if (starling_wire::now_secs() - ts).abs() > MAX_TS_SKEW_SECS {
                return Err((StatusCode::UNAUTHORIZED, "stale x-starling-ts"));
            }
            starling_wire::verify_owner_request_sig(&pubkey, method, path, ts, body, &sig)
        }
        None => starling_wire::verify_owner_sig(&pubkey, body, &sig),
    };
    if !valid {
        return Err((StatusCode::UNAUTHORIZED, "invalid signature"));
    }
    // Valid signature, but is it THIS Owner? Mismatch → 403.
    if pubkey.as_slice() != owner_pubkey.as_slice() {
        return Err((StatusCode::FORBIDDEN, "pubkey is not this relay owner"));
    }
    Ok(())
}
