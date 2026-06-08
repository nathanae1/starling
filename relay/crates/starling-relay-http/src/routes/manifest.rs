//! `GET /manifest?since=&until=` — CBOR `{pubkey, events, has_older}` (no
//! auth). Newest-first; clients page with `until = oldest.created_at - 1`.

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
}

pub async fn handler(State(ctx): State<OwnerCtx>, Query(q): Query<ManifestQuery>) -> Response {
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    // Fetch one extra to detect `has_older`.
    let rows = match events::manifest_page(
        &conn,
        &ctx.owner_pubkey,
        q.since,
        q.until,
        PAGE_LIMIT + 1,
    ) {
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
