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
    /// Envelope item type this payload was pushed as. Almost always
    /// `"event"`; stored verbatim so an unknown type round-trips (F4).
    pub item_type: String,
}

impl ServedEvent {
    /// A standard `"event"`-typed row (the overwhelmingly common case).
    pub fn event(
        pubkey: Vec<u8>,
        id: String,
        created_at: i64,
        msg_seq: i64,
        nonce: Vec<u8>,
        payload: Vec<u8>,
    ) -> Self {
        ServedEvent {
            pubkey,
            id,
            created_at,
            msg_seq,
            nonce,
            payload,
            item_type: "event".to_string(),
        }
    }
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
                (pubkey, id, created_at, msg_seq, nonce, payload, size, item_type)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                e.pubkey,
                e.id,
                e.created_at,
                e.msg_seq,
                e.nonce,
                e.payload,
                e.payload.len() as i64,
                e.item_type,
            ],
        )
        .context("insert served_event")?;
    Ok(n > 0)
}

/// Delete a batch of the Owner's event ids. Returns how many rows actually
/// existed (`missing = ids.len() - deleted`). The caller supplies the
/// transaction so a whole `POST /events/delete` body lands atomically.
pub fn delete_batch(conn: &Connection, pubkey: &[u8], ids: &[String]) -> Result<i64> {
    let mut stmt = conn
        .prepare("DELETE FROM served_events WHERE pubkey = ?1 AND id = ?2")
        .context("prepare served_events delete")?;
    let mut deleted = 0i64;
    for id in ids {
        deleted += stmt.execute(params![pubkey, id]).context("delete served_event")? as i64;
    }
    Ok(deleted)
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

/// One stored item served back in an `/events` page: its Envelope item type
/// and the opaque payload bytes.
#[derive(Debug, Clone)]
pub struct ServedPayload {
    pub item_type: String,
    pub payload: Vec<u8>,
}

/// One `/events` page plus the keyset cursor to fetch the next one.
#[derive(Debug)]
pub struct EventsPage {
    pub items: Vec<ServedPayload>,
    /// `(created_at, id)` of the last returned row when more rows remain
    /// past this page; `None` when the page completes the range.
    pub next: Option<(i64, String)>,
}

/// Oldest-first page of stored payloads for `/events`, ordered
/// `(created_at ASC, id ASC)`. `since` alone is an inclusive `created_at`
/// lower bound (legacy clients); with `since_id`, `(since, since_id)` is a
/// strict keyset cursor — rows ordered after it. A page ends at `max_rows`
/// rows or `byte_budget` payload bytes, whichever comes first; the first
/// row always fits, so a non-empty range never yields an empty page. Rows
/// past the cutoff are never materialized — payload bytes stream out of
/// the cursor one row at a time.
pub fn payloads_page(
    conn: &Connection,
    pubkey: &[u8],
    since: Option<i64>,
    since_id: Option<&str>,
    max_rows: i64,
    byte_budget: i64,
) -> Result<EventsPage> {
    let mut stmt = conn.prepare(
        "SELECT id, created_at, size, payload, item_type FROM served_events
         WHERE pubkey = ?1
           AND (?2 IS NULL
                OR (?3 IS NULL AND created_at >= ?2)
                OR created_at > ?2
                OR (created_at = ?2 AND id > ?3))
         ORDER BY created_at ASC, id ASC",
    )?;
    let mut rows = stmt
        .query(params![pubkey, since, since_id])
        .context("query payloads_page")?;
    let mut items: Vec<ServedPayload> = Vec::new();
    let mut bytes = 0i64;
    let mut last: Option<(i64, String)> = None;
    let mut truncated = false;
    while let Some(row) = rows.next().context("step payloads_page")? {
        let size: i64 = row.get(2)?;
        if !items.is_empty() && (items.len() as i64 >= max_rows || bytes + size > byte_budget) {
            truncated = true;
            break;
        }
        let id: String = row.get(0)?;
        let created_at: i64 = row.get(1)?;
        items.push(ServedPayload {
            payload: row.get(3)?,
            item_type: row.get(4)?,
        });
        bytes += size;
        last = Some((created_at, id));
    }
    Ok(EventsPage {
        items,
        next: if truncated { last } else { None },
    })
}
