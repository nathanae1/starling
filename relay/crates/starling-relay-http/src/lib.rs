//! Per-Owner HTTP router.
//!
//! One [`owner_router`] instance serves exactly one Owner: the Owner's
//! pubkey is captured in router state (not a query param), so the
//! Follower-facing reads need no auth and the Owner-facing writes are
//! gated by [`middleware::verify_owner_request`] against that one pubkey.
//! Arti reverse-proxies each Owner's `.onion` to the loopback port this
//! router binds to.

use std::path::PathBuf;

use axum::extract::DefaultBodyLimit;
use axum::routing::{get, post};
use axum::Router;
use starling_relay_storage::Db;

mod middleware;
pub mod rate_limit;
mod routes;

pub use rate_limit::{rate_limit_mw, RateLimiter};
pub use routes::internal;
pub use routes::media::{owner_shard_path, shard_path};

/// Max request body on Owner routes. Axum's 2 MiB default 413'd media
/// blobs; the old in-app Dart relay allowed 4 MiB.
pub const OWNER_BODY_LIMIT_BYTES: usize = 4 * 1024 * 1024;

/// Owner-router rate limit (matches the old Dart relay's 360/min).
const OWNER_RATE_PER_MIN: u32 = 360;
const OWNER_BURST: u32 = 60;

/// Storage caps (bytes). `0` means unlimited.
#[derive(Debug, Clone, Copy)]
pub struct Caps {
    /// Default per-Owner cap when the owner row's `storage_cap_bytes` is
    /// NULL.
    pub per_owner_default: i64,
    /// Host-wide cap across all Owners.
    pub disk_cap: i64,
}

impl Default for Caps {
    fn default() -> Self {
        Caps {
            per_owner_default: 1024 * 1024 * 1024, // 1 GiB
            disk_cap: 5 * 1024 * 1024 * 1024,      // 5 GiB
        }
    }
}

/// Everything one Owner's router needs.
#[derive(Clone)]
pub struct OwnerCtx {
    pub db: Db,
    /// Raw 32-byte Ed25519 pubkey this router speaks for.
    pub owner_pubkey: [u8; 32],
    /// Root media directory (`data_dir/media`). Blobs live under
    /// `media_dir/<owner_shard_path(owner_pubkey, hash)>` — namespaced per
    /// Owner so same-hash pushes from different Owners can't collide.
    pub media_dir: PathBuf,
    pub caps: Caps,
}

/// Build the per-Owner router with the relay endpoints. One rate-limit
/// bucket per router instance = per Owner endpoint (D6).
pub fn owner_router(ctx: OwnerCtx) -> Router {
    Router::new()
        .route("/status", get(routes::status::handler))
        .route("/manifest", get(routes::manifest::handler))
        .route("/events", get(routes::events::get_handler))
        .route("/events", post(routes::events::push_handler))
        .route("/media/:hash", get(routes::media::get_handler))
        .route("/media/:hash", post(routes::media::push_handler))
        .route("/media-manifest", get(routes::media::manifest_handler))
        .layer(DefaultBodyLimit::max(OWNER_BODY_LIMIT_BYTES))
        .layer(axum::middleware::from_fn_with_state(
            RateLimiter::per_minute(OWNER_RATE_PER_MIN, OWNER_BURST),
            rate_limit_mw,
        ))
        .with_state(ctx)
}
