//! `served_events` DAO — stored EncryptedEvent blobs + manifest queries.

use anyhow::{Context, Result};
use rusqlite::{params, Connection};

#[derive(Debug, Clone)]
pub struct ServedEvent {
    pub pubkey: Vec<u8>,
    pub id: String,
    pub created_at: i64,
    pub msg_seq: i64,
    pub nonce: Vec<u8>,
    pub payload: Vec<u8>,
}

/// One `{id, created_at}` manifest entry.
#[derive(Debug, Clone)]
pub struct ManifestRow {
    pub id: String,
    pub created_at: i64,
}

/// Idempotent insert. Returns `true` if a new row was stored, `false` if
/// `(pubkey, id)` already existed (re-push is a no-op).
pub fn insert(conn: &Connection, e: &ServedEvent) -> Result<bool> {
    let n = conn
        .execute(
            "INSERT OR IGNORE INTO served_events
                (pubkey, id, created_at, msg_seq, nonce, payload, size)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                e.pubkey,
                e.id,
                e.created_at,
                e.msg_seq,
                e.nonce,
                e.payload,
                e.payload.len() as i64
            ],
        )
        .context("insert served_event")?;
    Ok(n > 0)
}

/// Total payload bytes stored for an Owner (for cap enforcement).
pub fn total_bytes(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COALESCE(SUM(size), 0) FROM served_events WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("sum served_events size")
}

pub fn count(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COUNT(*) FROM served_events WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("count served_events")
}

/// Newest-first page of `{id, created_at}` for `/manifest`, ordered
/// `(created_at DESC, id DESC)`. `since`/`until` bound `created_at`
/// (inclusive). With `until_id`, `(until, until_id)` is a strict keyset
/// cursor — rows ordered after it — so same-second events truncated by
/// `limit` are picked up by the next page instead of skipped. Clients page
/// with `until = oldest.created_at, until_id = oldest.id`.
pub fn manifest_page(
    conn: &Connection,
    pubkey: &[u8],
    since: Option<i64>,
    until: Option<i64>,
    until_id: Option<&str>,
    limit: i64,
) -> Result<Vec<ManifestRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, created_at FROM served_events
         WHERE pubkey = ?1
           AND (?2 IS NULL OR created_at >= ?2)
           AND (?3 IS NULL
                OR (?4 IS NULL AND created_at <= ?3)
                OR created_at < ?3
                OR (created_at = ?3 AND id < ?4))
         ORDER BY created_at DESC, id DESC
         LIMIT ?5",
    )?;
    let rows = stmt
        .query_map(params![pubkey, since, until, until_id, limit], |row| {
            Ok(ManifestRow {
                id: row.get(0)?,
                created_at: row.get(1)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("query manifest page")?;
    Ok(rows)
}

/// Stored payloads for `/events`, chronological (oldest-first), filtered by
/// `since` (inclusive `created_at`).
pub fn payloads_since(
    conn: &Connection,
    pubkey: &[u8],
    since: Option<i64>,
    limit: i64,
) -> Result<Vec<Vec<u8>>> {
    let mut stmt = conn.prepare(
        "SELECT payload FROM served_events
         WHERE pubkey = ?1 AND (?2 IS NULL OR created_at >= ?2)
         ORDER BY created_at ASC
         LIMIT ?3",
    )?;
    let rows = stmt
        .query_map(params![pubkey, since, limit], |row| row.get::<_, Vec<u8>>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("query payloads_since")?;
    Ok(rows)
}
