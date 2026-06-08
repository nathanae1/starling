//! `GET /events?since=` (read, no auth) and `POST /events` (Owner-signed).

use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use serde::Deserialize;
use starling_relay_storage::{events, ServedEvent};
use starling_wire::envelope::build_events_envelope;
use starling_wire::event_header::EncryptedEventHeader;
use starling_wire::push::{PushBatch, PushReceipt};
use starling_wire::PROTOCOL_VERSION;

use super::{cbor_ok, internal};
use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

const PAGE_LIMIT: i64 = 500;

#[derive(Debug, Deserialize)]
pub struct EventsQuery {
    pub since: Option<i64>,
}

/// `GET /events` — CBOR Envelope of the stored EncryptedEvent payloads,
/// served back verbatim (the relay never re-encrypts).
pub async fn get_handler(State(ctx): State<OwnerCtx>, Query(q): Query<EventsQuery>) -> Response {
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    let payloads = match events::payloads_since(&conn, &ctx.owner_pubkey, q.since, PAGE_LIMIT) {
        Ok(p) => p,
        Err(e) => return internal(e),
    };
    let refs = payloads.iter().map(|v| v.as_slice());
    cbor_ok(build_events_envelope(PROTOCOL_VERSION, refs))
}

/// `POST /events` — Owner pushes a CBOR `{items:[{id, payload}]}` batch.
/// Each item's encrypted payload is stored verbatim after its cleartext
/// header is parsed for `created_at`/`msg_seq`/`nonce`. Malformed items are
/// counted as rejected.
pub async fn push_handler(
    State(ctx): State<OwnerCtx>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if let Err((code, msg)) = verify_owner_request(&headers, &body, &ctx.owner_pubkey) {
        return (code, msg).into_response();
    }
    let batch = match PushBatch::parse(&body) {
        Some(b) => b,
        None => return (StatusCode::BAD_REQUEST, "malformed cbor body").into_response(),
    };
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };

    let mut accepted = 0i64;
    let mut rejected = 0i64;
    for item in batch.items {
        let Some(header) = EncryptedEventHeader::parse(&item.payload) else {
            rejected += 1;
            continue;
        };
        let event = ServedEvent {
            pubkey: ctx.owner_pubkey.to_vec(),
            id: item.id,
            created_at: header.created_at,
            msg_seq: header.msg_seq,
            nonce: header.nonce,
            payload: item.payload,
        };
        // Idempotent: a duplicate `(pubkey, id)` still counts as accepted
        // (the content is present), so the phone's re-push converges.
        match events::insert(&conn, &event) {
            Ok(_) => accepted += 1,
            Err(_) => rejected += 1,
        }
    }
    let receipt = PushReceipt { accepted, rejected };
    (
        StatusCode::ACCEPTED,
        [(axum::http::header::CONTENT_TYPE, "application/cbor")],
        receipt.to_cbor(),
    )
        .into_response()
}
