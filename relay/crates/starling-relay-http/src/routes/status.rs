//! `GET /status` — JSON identity + storage stats (no auth).

use axum::extract::State;
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use starling_relay_storage::{events, media};
use starling_wire::manifest::StatusJson;
use starling_wire::{crockford_base32_encode, PROTOCOL_VERSION};

use super::internal;
use crate::OwnerCtx;

pub async fn handler(State(ctx): State<OwnerCtx>) -> Response {
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    let event_count = match events::count(&conn, &ctx.owner_pubkey) {
        Ok(n) => n,
        Err(e) => return internal(e),
    };
    let media_storage_used = match media::total_bytes(&conn, &ctx.owner_pubkey) {
        Ok(n) => n,
        Err(e) => return internal(e),
    };
    let status = StatusJson {
        pubkey: crockford_base32_encode(&ctx.owner_pubkey),
        version: PROTOCOL_VERSION.to_string(),
        event_count,
        media_storage_used,
    };
    let body = serde_json::to_vec(&status).expect("serialize StatusJson");
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json; charset=utf-8")],
        body,
    )
        .into_response()
}
