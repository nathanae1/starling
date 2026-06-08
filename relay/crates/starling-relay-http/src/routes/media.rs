//! `GET /media/<hash>` (read, no auth) and `POST /media/<hash>`
//! (Owner-signed). Blobs are the raw `nonce || ciphertext` form; the relay
//! never decrypts.

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use starling_relay_storage::{media, owners, ServedMedia};

use super::{internal, now_secs};
use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

/// On-disk shard for a media hash: `<hex[0:2]>/<hex[0:4]>/<hexhash>`,
/// matching the phone's `encrypted_media_paths.dart` layout.
pub fn shard_path(hash: &str) -> String {
    format!("{}/{}/{}", &hash[0..2], &hash[0..4], hash)
}

fn is_valid_hash(hash: &str) -> bool {
    hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub async fn get_handler(State(ctx): State<OwnerCtx>, Path(hash): Path<String>) -> Response {
    if !is_valid_hash(&hash) {
        return (StatusCode::BAD_REQUEST, "invalid hash").into_response();
    }
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    let row = match media::get(&conn, &ctx.owner_pubkey, &hash) {
        Ok(r) => r,
        Err(e) => return internal(e),
    };
    let Some(row) = row else {
        return (StatusCode::NOT_FOUND, "not found").into_response();
    };
    let full = ctx.media_dir.join(&row.path);
    match tokio::fs::read(&full).await {
        Ok(bytes) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, "application/octet-stream")],
            bytes,
        )
            .into_response(),
        Err(_) => (StatusCode::NOT_FOUND, "not found").into_response(),
    }
}

pub async fn push_handler(
    State(ctx): State<OwnerCtx>,
    Path(hash): Path<String>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if !is_valid_hash(&hash) {
        return (StatusCode::BAD_REQUEST, "invalid hash").into_response();
    }
    if let Err((code, msg)) = verify_owner_request(&headers, &body, &ctx.owner_pubkey) {
        return (code, msg).into_response();
    }
    let conn = match ctx.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };

    // Idempotent: if we already have this blob, accept without rewriting.
    match media::get(&conn, &ctx.owner_pubkey, &hash) {
        Ok(Some(_)) => return StatusCode::ACCEPTED.into_response(),
        Ok(None) => {}
        Err(e) => return internal(e),
    }

    // Per-Owner cap enforcement (host-wide cap enforced separately at the
    // supervisor level). 507 when the new blob would exceed it.
    let used = match media::total_bytes(&conn, &ctx.owner_pubkey) {
        Ok(n) => n,
        Err(e) => return internal(e),
    };
    let owner = match owners::get(&conn, &ctx.owner_pubkey) {
        Ok(o) => o,
        Err(e) => return internal(e),
    };
    let cap = owner
        .and_then(|o| o.storage_cap_bytes)
        .unwrap_or(ctx.caps.per_owner_default);
    if cap > 0 && used + body.len() as i64 > cap {
        return (StatusCode::INSUFFICIENT_STORAGE, "owner storage cap exceeded").into_response();
    }

    let rel = shard_path(&hash);
    let full = ctx.media_dir.join(&rel);
    if let Some(parent) = full.parent() {
        if let Err(e) = tokio::fs::create_dir_all(parent).await {
            return internal(anyhow::Error::from(e));
        }
    }
    if let Err(e) = tokio::fs::write(&full, &body).await {
        return internal(anyhow::Error::from(e));
    }

    let record = ServedMedia {
        pubkey: ctx.owner_pubkey.to_vec(),
        hash,
        size: body.len() as i64,
        created_at: now_secs(),
        path: rel,
    };
    if let Err(e) = media::insert(&conn, &record) {
        return internal(e);
    }
    StatusCode::ACCEPTED.into_response()
}
