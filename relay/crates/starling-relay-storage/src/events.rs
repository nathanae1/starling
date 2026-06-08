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
                (pubkey, id, created_at, msg_seq, nonce, payload)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![e.pubkey, e.id, e.created_at, e.msg_seq, e.nonce, e.payload],
        )
        .context("insert served_event")?;
    Ok(n > 0)
}

pub fn count(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COUNT(*) FROM served_events WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("count served_events")
}

/// Newest-first page of `{id, created_at}` for `/manifest`. `since`/`until`
/// bound `created_at` (inclusive). Returns up to `limit` rows.
pub fn manifest_page(
    conn: &Connection,
    pubkey: &[u8],
    since: Option<i64>,
    until: Option<i64>,
    limit: i64,
) -> Result<Vec<ManifestRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, created_at FROM served_events
         WHERE pubkey = ?1
           AND (?2 IS NULL OR created_at >= ?2)
           AND (?3 IS NULL OR created_at <= ?3)
         ORDER BY created_at DESC
         LIMIT ?4",
    )?;
    let rows = stmt
        .query_map(params![pubkey, since, until, limit], |row| {
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
