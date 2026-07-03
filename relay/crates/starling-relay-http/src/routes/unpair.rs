//! `POST /unpair` (Owner-signed, A3) — the Owner tells the relay it is
//! unpairing. The relay wipes the Owner (row + media + onion) via the
//! supervisor, so relay-primary Followers' probes fail fast and they fall
//! back to the phone instead of reading a permanently-stale endpoint.

use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;

use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

/// Verifies the Owner signature, then triggers the wipe through the
/// supervisor-wired [`crate::UnpairHandle`] and answers `200` immediately.
/// The handle is fire-and-forget by contract: the wipe aborts this very
/// router's serving task, so it runs after a grace delay on the
/// supervisor side to let this response flush.
pub async fn handler(State(ctx): State<OwnerCtx>, headers: HeaderMap, body: Bytes) -> Response {
    if let Err((code, msg)) =
        verify_owner_request(&headers, "POST", "/unpair", &body, &ctx.owner_pubkey)
    {
        return (code, msg).into_response();
    }
    match &ctx.unpair {
        Some(unpair) => {
            unpair();
            StatusCode::OK.into_response()
        }
        None => (StatusCode::NOT_IMPLEMENTED, "unpair not wired").into_response(),
    }
}
