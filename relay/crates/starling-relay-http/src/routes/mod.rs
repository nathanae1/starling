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

/// Map any internal error to a `500`. `pub` — the admin crate shares it.
pub fn internal(err: anyhow::Error) -> Response {
    log::error!("internal error: {err:?}");
    (StatusCode::INTERNAL_SERVER_ERROR, "internal error").into_response()
}

pub(crate) use starling_wire::now_secs;
