//! `GET /status` — JSON identity + storage stats (no auth).

use axum::extract::State;
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use starling_relay_storage::{accounting, events, media, owners, voice_slots};
use starling_wire::manifest::{StatusJson, VoiceStatusJson};
use starling_wire::{crockford_base32_encode, PROTOCOL_VERSION};

use super::internal;
use crate::OwnerCtx;

pub async fn handler(State(ctx): State<OwnerCtx>) -> Response {
    let pubkey = ctx.owner_pubkey;
    let per_owner_default = ctx.caps.per_owner_default;
    let counts = ctx
        .db
        .run(move |conn| {
            let event_count = events::count(conn, &pubkey)?;
            let media_storage_used = media::total_bytes(conn, &pubkey)?;
            let storage_used = accounting::owner_usage(conn, &pubkey)?;
            let storage_limit = owners::get(conn, &pubkey)?
                .and_then(|o| o.storage_cap_bytes)
                .unwrap_or(per_owner_default);
            let voice_slot_count = voice_slots::count_for_owner(conn, &pubkey)?;
            Ok((event_count, media_storage_used, storage_used, storage_limit, voice_slot_count))
        })
        .await;
    let (event_count, media_storage_used, storage_used, storage_limit, voice_slot_count) =
        match counts {
            Ok(c) => c,
            Err(e) => return internal(e),
        };
    // Always present: the phone capability-detects voice hosting from this
    // field at pair/reconcile time (Plan 20).
    let voice = match &ctx.voice {
        Some(v) => VoiceStatusJson {
            enabled: true,
            max_participants: v.max_participants,
            slot_count: voice_slot_count,
        },
        None => VoiceStatusJson::disabled(),
    };
    let status = StatusJson {
        pubkey: crockford_base32_encode(&ctx.owner_pubkey),
        version: PROTOCOL_VERSION.to_string(),
        event_count,
        storage_used,
        storage_limit,
        media_storage_used,
        voice,
    };
    let body = serde_json::to_vec(&status).expect("serialize StatusJson");
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json; charset=utf-8")],
        body,
    )
        .into_response()
}
