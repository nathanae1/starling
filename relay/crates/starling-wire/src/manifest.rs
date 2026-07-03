//! `/manifest` and `/status` response shapes
//! (`server/handlers/{manifest,status}_handler.dart`).
//!
//! `pubkey` is Crockford base32 text on both — NOT the base64 form used in
//! the `X-Starling-Pubkey` auth header. Encode with
//! [`crate::crockford_base32_encode`] from the raw 32-byte BLOB the relay
//! stores.

use serde::Serialize;

/// One `{id, created_at}` entry in a manifest page.
#[derive(Debug, Clone, Serialize)]
pub struct ManifestEntry {
    pub id: String,
    pub created_at: i64,
}

/// `GET /manifest` CBOR body. The relay omits the optional `new_feed_key`
/// field the phone may attach — it has no per-follower key-distribution
/// state (a known v1 limitation; rotation keys come from the phone).
#[derive(Debug, Clone, Serialize)]
pub struct ManifestPage {
    /// Owner pubkey, Crockford base32.
    pub pubkey: String,
    pub events: Vec<ManifestEntry>,
    pub has_older: bool,
}

impl ManifestPage {
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize ManifestPage");
        buf
    }
}

/// `GET /media-manifest` CBOR body (relay-only, Owner-signed): the media
/// hashes stored for the Owner, `hash ASC`, keyset-paged via `?after=`.
#[derive(Debug, Clone, Serialize)]
pub struct MediaManifestPage {
    pub hashes: Vec<String>,
    pub has_older: bool,
}

impl MediaManifestPage {
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize MediaManifestPage");
        buf
    }
}

/// `GET /status` JSON body.
#[derive(Debug, Clone, Serialize)]
pub struct StatusJson {
    /// Owner pubkey, Crockford base32.
    pub pubkey: String,
    pub version: String,
    pub event_count: i64,
    /// Total bytes stored for this Owner: event payloads + media blobs.
    /// This is what the cap and 507 threshold actually count.
    pub storage_used: i64,
    /// The Owner's storage cap in bytes, or `0` for unlimited. The phone
    /// uses `(storage_used, storage_limit)` to predict a 507 before pushing.
    pub storage_limit: i64,
    /// Media-only bytes. Retained for older phones that read this field;
    /// `storage_used` supersedes it.
    pub media_storage_used: i64,
}
