//! `GET /media/<hash>` (read, no auth), `POST /media/<hash>` and
//! `POST /media/delete` (Owner-signed), and `GET /media-manifest`
//! (Owner-signed presence list for the phone's reconcile). Blobs are the
//! raw `nonce || ciphertext` form; the relay never decrypts.

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use bytes::Bytes;
use serde::Deserialize;
use starling_relay_storage::accounting::{self, CapCheck};
use starling_relay_storage::{immediate_tx, media, owners, ServedMedia};
use starling_wire::delete::{DeleteMediaRequest, DeleteReceipt};
use starling_wire::manifest::MediaManifestPage;

use super::{cbor_ok, internal, now_secs};
use crate::middleware::verify_owner_request;
use crate::OwnerCtx;

const MANIFEST_PAGE_LIMIT: i64 = 1000;

/// On-disk shard for a media hash: `<hex[0:2]>/<hex[0:4]>/<hexhash>`,
/// matching the phone's `encrypted_media_paths.dart` layout.
pub fn shard_path(hash: &str) -> String {
    format!("{}/{}/{}", &hash[0..2], &hash[0..4], hash)
}

/// Owner-namespaced blob path: `<owner_hex>/<shard_path(hash)>`. Blobs are
/// ciphertext keyed by the *plaintext* hash, so the relay can't verify a
/// body against the URL hash — namespacing per Owner is what stops one
/// paired Owner from clobbering another's blob at the same hash.
pub fn owner_shard_path(owner_pubkey: &[u8; 32], hash: &str) -> String {
    format!("{}/{}", hex::encode(owner_pubkey), shard_path(hash))
}

fn is_valid_hash(hash: &str) -> bool {
    hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub async fn get_handler(State(ctx): State<OwnerCtx>, Path(hash): Path<String>) -> Response {
    if !is_valid_hash(&hash) {
        return (StatusCode::BAD_REQUEST, "invalid hash").into_response();
    }
    let pubkey = ctx.owner_pubkey;
    let lookup_hash = hash.clone();
    let row = ctx
        .db
        .run(move |conn| media::get(conn, &pubkey, &lookup_hash))
        .await;
    let row = match row {
        Ok(r) => r,
        Err(e) => return internal(e),
    };
    let Some(row) = row else {
        return (StatusCode::NOT_FOUND, "not found").into_response();
    };
    // Stream the blob — bodies are unbounded ciphertext and buffering them
    // whole lets one slow Tor reader pin megabytes of RAM per request.
    let full = ctx.media_dir.join(&row.path);
    let file = match tokio::fs::File::open(&full).await {
        Ok(f) => f,
        Err(_) => return (StatusCode::NOT_FOUND, "not found").into_response(),
    };
    let len = match file.metadata().await {
        Ok(m) => m.len(),
        Err(_) => return (StatusCode::NOT_FOUND, "not found").into_response(),
    };
    (
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, "application/octet-stream".to_string()),
            (header::CONTENT_LENGTH, len.to_string()),
        ],
        axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(file)),
    )
        .into_response()
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
    let req_path = format!("/media/{hash}");
    if let Err((code, msg)) = verify_owner_request(&headers, "POST", &req_path, &body, &ctx.owner_pubkey) {
        return (code, msg).into_response();
    }

    // Idempotency check, cap check, blob write, and record insert all run
    // in one blocking closure — the fs write happens via `std::fs` so no
    // pooled connection is ever held across an await.
    let pubkey = ctx.owner_pubkey;
    let media_dir = ctx.media_dir.clone();
    let per_owner_default = ctx.caps.per_owner_default;
    let disk_cap = ctx.caps.disk_cap;
    let outcome = ctx
        .db
        .run(move |conn| {
            // IMMEDIATE: write lock up front so the cap check below can't
            // race a concurrent push, and same-hash pushes serialize
            // instead of interleaving their file writes.
            let tx = immediate_tx(conn)?;

            let rel = owner_shard_path(&pubkey, &hash);
            let full = media_dir.join(&rel);

            // Idempotent re-push: accept without rewriting only when the
            // row AND the on-disk blob both match the incoming size. A torn
            // or clobbered write falls through and heals via the rewrite.
            let existing = media::get(&tx, &pubkey, &hash)?;
            if let Some(ref ex) = existing {
                let disk_len = std::fs::metadata(&full).map(|m| m.len() as i64).ok();
                if ex.size == body.len() as i64 && disk_len == Some(ex.size) {
                    return Ok(PushOutcome::Accepted);
                }
            }

            // Cap check at the shared accounting chokepoint (D4). 507 when
            // the blob would bust the Owner's cap or the host disk cap. A
            // replacement is charged only for the delta over the recorded
            // size, so healing a torn blob can't 507 at the cap.
            let owner_cap = owners::get(&tx, &pubkey)?
                .and_then(|o| o.storage_cap_bytes)
                .unwrap_or(per_owner_default);
            let stored = existing.as_ref().map(|e| e.size).unwrap_or(0);
            let incoming = (body.len() as i64 - stored).max(0);
            match accounting::check_capacity(&tx, &pubkey, incoming, owner_cap, disk_cap)? {
                CapCheck::Ok => {}
                CapCheck::OwnerExceeded => {
                    return Ok(PushOutcome::CapExceeded("owner storage cap exceeded"))
                }
                CapCheck::HostExceeded => {
                    return Ok(PushOutcome::CapExceeded("relay storage cap exceeded"))
                }
            }

            if let Some(parent) = full.parent() {
                std::fs::create_dir_all(parent)?;
            }
            // Write-then-rename: a crash mid-write can't leave a torn blob
            // at the final path, which the idempotency check above would
            // otherwise pin forever.
            let tmp = full.with_extension("tmp");
            std::fs::write(&tmp, &body)?;
            std::fs::rename(&tmp, &full)?;

            let record = ServedMedia {
                pubkey: pubkey.to_vec(),
                hash,
                size: body.len() as i64,
                created_at: now_secs(),
                path: rel,
            };
            media::upsert(&tx, &record)?;
            tx.commit()?;
            Ok(PushOutcome::Accepted)
        })
        .await;
    match outcome {
        Ok(PushOutcome::Accepted) => StatusCode::ACCEPTED.into_response(),
        Ok(PushOutcome::CapExceeded(msg)) => {
            (StatusCode::INSUFFICIENT_STORAGE, msg).into_response()
        }
        Err(e) => internal(e),
    }
}

enum PushOutcome {
    Accepted,
    CapExceeded(&'static str),
}

/// `POST /media/delete` — Owner removes stored blobs by hash. CBOR
/// `{hashes:[...]}` → `200 {deleted, missing}`; `400` if ANY hash is
/// malformed (a bad hash is a client bug, not a missing blob). Rows are
/// deleted in one transaction, then files are unlinked best-effort AFTER
/// the commit — a crash in between leaves orphan files that the startup GC
/// sweeps, never a row pointing at nothing.
///
/// Routed at the static `/media/delete` segment, which axum matches before
/// the `/media/:hash` capture; `"delete"` also fails `is_valid_hash`, so
/// the two routes can't collide even without that precedence.
pub async fn delete_handler(
    State(ctx): State<OwnerCtx>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if let Err((code, msg)) =
        verify_owner_request(&headers, "POST", "/media/delete", &body, &ctx.owner_pubkey)
    {
        return (code, msg).into_response();
    }
    let req = match DeleteMediaRequest::parse(&body) {
        Some(r) => r,
        None => return (StatusCode::BAD_REQUEST, "malformed cbor body").into_response(),
    };
    if !req.hashes.iter().all(|h| is_valid_hash(h)) {
        return (StatusCode::BAD_REQUEST, "invalid hash").into_response();
    }
    let pubkey = ctx.owner_pubkey;
    let media_dir = ctx.media_dir.clone();
    let receipt = ctx
        .db
        .run(move |conn| {
            let tx = immediate_tx(conn)?;
            let requested = req.hashes.len() as i64;
            let mut deleted = 0i64;
            let mut unlink = Vec::new();
            for hash in &req.hashes {
                if let Some(row) = media::delete(&tx, &pubkey, hash)? {
                    deleted += 1;
                    unlink.push(row.path);
                }
            }
            tx.commit()?;
            for rel in unlink {
                if let Err(e) = std::fs::remove_file(media_dir.join(&rel)) {
                    if e.kind() != std::io::ErrorKind::NotFound {
                        log::warn!("media delete: could not unlink {rel}: {e}");
                    }
                }
            }
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

#[derive(Debug, Deserialize)]
pub struct MediaManifestQuery {
    pub after: Option<String>,
}

/// `GET /media-manifest?after=` — the Owner's stored media hashes so its
/// reconcile can diff presence (D8) without N HEAD round-trips over Tor.
/// Owner-signed (over the empty body): this is Owner tooling, and Followers
/// have no use for it. The hashes are already known to the relay (they key
/// the blobs), so serving them to their Owner leaks nothing new.
pub async fn manifest_handler(
    State(ctx): State<OwnerCtx>,
    headers: HeaderMap,
    Query(q): Query<MediaManifestQuery>,
) -> Response {
    if let Err((code, msg)) =
        verify_owner_request(&headers, "GET", "/media-manifest", b"", &ctx.owner_pubkey)
    {
        return (code, msg).into_response();
    }
    let pubkey = ctx.owner_pubkey;
    // One extra row to detect `has_older`, mirroring `/manifest`.
    let rows = ctx
        .db
        .run(move |conn| {
            media::hashes_page(conn, &pubkey, q.after.as_deref(), MANIFEST_PAGE_LIMIT + 1)
        })
        .await;
    let rows = match rows {
        Ok(r) => r,
        Err(e) => return internal(e),
    };
    let has_older = rows.len() as i64 > MANIFEST_PAGE_LIMIT;
    let page = MediaManifestPage {
        hashes: rows.into_iter().take(MANIFEST_PAGE_LIMIT as usize).collect(),
        has_older,
    };
    cbor_ok(page.to_cbor())
}
