//! The six relay endpoints, split by resource.

pub mod events;
pub mod manifest;
pub mod media;
pub mod status;

use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};

/// CBOR `200 OK`.
pub(crate) fn cbor_ok(body: Vec<u8>) -> Response {
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/cbor")],
        body,
    )
        .into_response()
}

/// Map any storage error to a `500`.
pub(crate) fn internal(err: anyhow::Error) -> Response {
    log::error!("relay http internal error: {err:?}");
    (StatusCode::INTERNAL_SERVER_ERROR, "internal error").into_response()
}

/// Current unix time in seconds.
pub(crate) fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
