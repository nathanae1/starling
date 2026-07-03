//! `GET /events?since=` (read, no auth), `POST /events` (Owner-signed),
//! and `POST /events/delete` (Owner-signed).

use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use serde::Deserialize;
use starling_relay_storage::accounting::{self, CapCheck};
use starling_relay_storage::{events, immediate_tx, owners, ServedEvent};
use starling_wire::delete::{DeleteEventsRequest, DeleteReceipt};
use starling_wire::envelope::build_typed_envelope_page;
use starling_wire::event_header::EncryptedEventHeader;
use starling_wire::push::{PushBatch, PushReceipt};
use starling_wire::PROTOCOL_VERSION;

use super::{cbor_ok, internal};
use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

const PAGE_LIMIT: i64 = 500;

/// Payload bytes per `/events` page. This bounds handler memory on an
/// unauthenticated route — a row-count-only limit let one request
/// materialize up to 500 × 4 MiB payloads. Matches [`crate::OWNER_BODY_LIMIT_BYTES`]
/// so any single stored payload always fits in a page by itself.
const PAGE_BYTE_BUDGET: i64 = 4 * 1024 * 1024;

/// Longest accepted `PushItem.id`. Event ids are 52-char Crockford base32;
/// without a bound the TEXT column is an unaccounted byte sink that
/// bypasses the storage caps.
const MAX_ID_LEN: usize = 64;

#[derive(Debug, Deserialize)]
pub struct EventsQuery {
    pub since: Option<i64>,
    pub since_id: Option<String>,
}

/// `GET /events` — CBOR Envelope of the stored EncryptedEvent payloads,
/// served back verbatim (the relay never re-encrypts). Pages oldest-first
/// by `(created_at, id)` keyset; a truncated page carries the cursor for
/// the next one in `extensions["next"]`, which clients echo back as
/// `?since=&since_id=`.
pub async fn get_handler(State(ctx): State<OwnerCtx>, Query(q): Query<EventsQuery>) -> Response {
    let pubkey = ctx.owner_pubkey;
    let page = ctx
        .db
        .run(move |conn| {
            events::payloads_page(
                conn,
                &pubkey,
                q.since,
                q.since_id.as_deref(),
                PAGE_LIMIT,
                PAGE_BYTE_BUDGET,
            )
        })
        .await;
    let page = match page {
        Ok(p) => p,
        Err(e) => return internal(e),
    };
    let items = page
        .items
        .iter()
        .map(|i| (i.item_type.as_str(), i.payload.as_slice()));
    let next = page.next.as_ref().map(|(at, id)| (*at, id.as_str()));
    cbor_ok(build_typed_envelope_page(PROTOCOL_VERSION, items, next))
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
    if let Err((code, msg)) = verify_owner_request(&headers, "POST", "/events", &body, &ctx.owner_pubkey) {
        return (code, msg).into_response();
    }
    let batch = match PushBatch::parse(&body) {
        Some(b) => b,
        None => return (StatusCode::BAD_REQUEST, "malformed cbor body").into_response(),
    };

    let pubkey = ctx.owner_pubkey;
    let per_owner_default = ctx.caps.per_owner_default;
    let disk_cap = ctx.caps.disk_cap;
    let outcome = ctx
        .db
        .run(move |conn| {
            // One IMMEDIATE transaction for cap check + batch insert: the
            // write lock is taken before the usage read, so two concurrent
            // pushes can't both pass the check against the same baseline.
            // (Also one fsync for the whole batch — per-item autocommit
            // crawls on a backfill.)
            let tx = immediate_tx(conn)?;

            // Cap check at the shared accounting chokepoint (D4). 507 when
            // the batch would bust the Owner's cap or the host disk cap.
            let owner_cap = owners::get(&tx, &pubkey)?
                .and_then(|o| o.storage_cap_bytes)
                .unwrap_or(per_owner_default);
            let incoming: i64 = batch.items.iter().map(|i| i.payload.len() as i64).sum();
            match accounting::check_capacity(&tx, &pubkey, incoming, owner_cap, disk_cap)? {
                CapCheck::Ok => {}
                CapCheck::OwnerExceeded => {
                    return Ok(PushOutcome::CapExceeded("owner storage cap exceeded"))
                }
                CapCheck::HostExceeded => {
                    return Ok(PushOutcome::CapExceeded("relay storage cap exceeded"))
                }
            }

            let now = super::now_secs();
            let mut accepted = 0i64;
            let mut rejected = 0i64;
            for item in batch.items {
                // `rejected` counts items the phone should NOT retry:
                // malformed payloads and oversized ids. Storage errors are
                // not the phone's fault — they propagate as a 500 so the
                // whole batch is retried instead of silently dropped.
                if item.id.len() > MAX_ID_LEN {
                    rejected += 1;
                    continue;
                }
                let event = if item.item_type == "event" {
                    // Standard event: the cleartext header gives ordering +
                    // the msg_seq media decryption needs. A payload that
                    // doesn't parse as one is malformed → rejected.
                    let Some(header) = EncryptedEventHeader::parse(&item.payload) else {
                        rejected += 1;
                        continue;
                    };
                    ServedEvent {
                        pubkey: pubkey.to_vec(),
                        id: item.id,
                        created_at: header.created_at,
                        msg_seq: header.msg_seq,
                        nonce: header.nonce,
                        payload: item.payload,
                        item_type: item.item_type,
                    }
                } else {
                    // Unknown item type: stored opaquely for round-trip
                    // (F4). The relay can't read a header it doesn't
                    // understand, so it orders by arrival time.
                    ServedEvent {
                        pubkey: pubkey.to_vec(),
                        id: item.id,
                        created_at: now,
                        msg_seq: 0,
                        nonce: Vec::new(),
                        payload: item.payload,
                        item_type: item.item_type,
                    }
                };
                // Idempotent: a duplicate `(pubkey, id)` still counts as
                // accepted (the content is present), so the phone's re-push
                // converges.
                events::insert(&tx, &event)?;
                accepted += 1;
            }
            tx.commit()?;
            Ok(PushOutcome::Stored(PushReceipt { accepted, rejected }))
        })
        .await;
    match outcome {
        Ok(PushOutcome::Stored(receipt)) => (
            StatusCode::ACCEPTED,
            [(axum::http::header::CONTENT_TYPE, "application/cbor")],
            receipt.to_cbor(),
        )
            .into_response(),
        Ok(PushOutcome::CapExceeded(msg)) => {
            (StatusCode::INSUFFICIENT_STORAGE, msg).into_response()
        }
        Err(e) => internal(e),
    }
}

enum PushOutcome {
    Stored(PushReceipt),
    CapExceeded(&'static str),
}

/// `POST /events/delete` — Owner removes stored events by id. CBOR
/// `{ids:[...]}` → `200 {deleted, missing}`. One transaction for the whole
/// batch; idempotent (absent ids count as `missing`, never an error), so
/// the phone's crashed-and-retried delete pass converges.
pub async fn delete_handler(
    State(ctx): State<OwnerCtx>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if let Err((code, msg)) =
        verify_owner_request(&headers, "POST", "/events/delete", &body, &ctx.owner_pubkey)
    {
        return (code, msg).into_response();
    }
    let req = match DeleteEventsRequest::parse(&body) {
        Some(r) => r,
        None => return (StatusCode::BAD_REQUEST, "malformed cbor body").into_response(),
    };
    let pubkey = ctx.owner_pubkey;
    let receipt = ctx
        .db
        .run(move |conn| {
            let tx = immediate_tx(conn)?;
            let requested = req.ids.len() as i64;
            let deleted = events::delete_batch(&tx, &pubkey, &req.ids)?;
            tx.commit()?;
            Ok(DeleteReceipt {
                deleted,
                missing: requested - deleted,
            })
        })
        .await;
    match receipt {
        Ok(r) => cbor_ok(r.to_cbor()),
        Err(e) => internal(e),
    }
}
