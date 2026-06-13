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
    let pubkey = ctx.owner_pubkey;
    let counts = ctx
        .db
        .run(move |conn| {
            let event_count = events::count(conn, &pubkey)?;
            let media_storage_used = media::total_bytes(conn, &pubkey)?;
            Ok((event_count, media_storage_used))
        })
        .await;
    let (event_count, media_storage_used) = match counts {
        Ok(c) => c,
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
