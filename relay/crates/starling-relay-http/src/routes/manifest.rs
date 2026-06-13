//! `GET /manifest?since=&until=&until_id=` — CBOR `{pubkey, events,
//! has_older}` (no auth). Newest-first `(created_at DESC, id DESC)`; clients
//! page with `until = oldest.created_at, until_id = oldest.id` (the pair is
//! a strict keyset cursor, so same-second events are never skipped). Bare
//! `until` keeps the old inclusive `created_at <= until` semantics.

use axum::extract::{Query, State};
use axum::response::Response;
use serde::Deserialize;
use starling_relay_storage::events;
use starling_wire::crockford_base32_encode;
use starling_wire::manifest::{ManifestEntry, ManifestPage};

use super::{cbor_ok, internal};
use crate::OwnerCtx;

const PAGE_LIMIT: i64 = 1000;

#[derive(Debug, Deserialize)]
pub struct ManifestQuery {
    pub since: Option<i64>,
    pub until: Option<i64>,
    pub until_id: Option<String>,
}

pub async fn handler(State(ctx): State<OwnerCtx>, Query(q): Query<ManifestQuery>) -> Response {
    let pubkey = ctx.owner_pubkey;
    // Fetch one extra to detect `has_older`.
    let rows = ctx
        .db
        .run(move |conn| {
            events::manifest_page(
                conn,
                &pubkey,
                q.since,
                q.until,
                q.until_id.as_deref(),
                PAGE_LIMIT + 1,
            )
        })
        .await;
    let rows = match rows {
        Ok(r) => r,
        Err(e) => return internal(e),
    };
    let has_older = rows.len() as i64 > PAGE_LIMIT;
    let events = rows
        .into_iter()
        .take(PAGE_LIMIT as usize)
        .map(|r| ManifestEntry {
            id: r.id,
            created_at: r.created_at,
        })
        .collect();
    let page = ManifestPage {
        pubkey: crockford_base32_encode(&ctx.owner_pubkey),
        events,
        has_older,
    };
    cbor_ok(page.to_cbor())
}
