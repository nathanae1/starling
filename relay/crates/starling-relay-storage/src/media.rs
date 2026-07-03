//! `served_media` DAO — metadata for encrypted media blobs on disk.

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone)]
pub struct ServedMedia {
    pub pubkey: Vec<u8>,
    pub hash: String,
    pub size: i64,
    pub created_at: i64,
    pub path: String,
}

/// Idempotent insert. Returns `true` if a new row was stored.
pub fn insert(conn: &Connection, m: &ServedMedia) -> Result<bool> {
    let n = conn
        .execute(
            "INSERT OR IGNORE INTO served_media
                (pubkey, hash, size, created_at, path)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![m.pubkey, m.hash, m.size, m.created_at, m.path],
        )
        .context("insert served_media")?;
    Ok(n > 0)
}

/// Insert or refresh the row for `(pubkey, hash)`. A re-push may replace a
/// torn or clobbered blob, so `size`/`created_at` must track the bytes
/// actually written to disk rather than the first push's.
pub fn upsert(conn: &Connection, m: &ServedMedia) -> Result<()> {
    conn.execute(
        "INSERT INTO served_media (pubkey, hash, size, created_at, path)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(pubkey, hash) DO UPDATE SET
             size = excluded.size,
             created_at = excluded.created_at,
             path = excluded.path",
        params![m.pubkey, m.hash, m.size, m.created_at, m.path],
    )
    .context("upsert served_media")?;
    Ok(())
}

pub fn get(conn: &Connection, pubkey: &[u8], hash: &str) -> Result<Option<ServedMedia>> {
    conn.query_row(
        "SELECT pubkey, hash, size, created_at, path
         FROM served_media WHERE pubkey = ?1 AND hash = ?2",
        params![pubkey, hash],
        |row| {
            Ok(ServedMedia {
                pubkey: row.get(0)?,
                hash: row.get(1)?,
                size: row.get(2)?,
                created_at: row.get(3)?,
                path: row.get(4)?,
            })
        },
    )
    .optional()
    .context("get served_media")
}

/// Delete the `(pubkey, hash)` row, returning the removed row so the
/// caller can unlink its file AFTER the delete commits (row first, file
/// second — a crash in between leaves an orphan file for startup GC, never
/// a row pointing at nothing). `None` when no row existed.
pub fn delete(conn: &Connection, pubkey: &[u8], hash: &str) -> Result<Option<ServedMedia>> {
    let row = get(conn, pubkey, hash)?;
    if row.is_some() {
        conn.execute(
            "DELETE FROM served_media WHERE pubkey = ?1 AND hash = ?2",
            params![pubkey, hash],
        )
        .context("delete served_media")?;
    }
    Ok(row)
}

/// Every media row stored for an Owner — the startup GC's input for
/// diffing DB state against the files actually on disk.
pub fn rows_for_owner(conn: &Connection, pubkey: &[u8]) -> Result<Vec<ServedMedia>> {
    let mut stmt = conn.prepare(
        "SELECT pubkey, hash, size, created_at, path
         FROM served_media WHERE pubkey = ?1",
    )?;
    let rows = stmt
        .query_map(params![pubkey], |row| {
            Ok(ServedMedia {
                pubkey: row.get(0)?,
                hash: row.get(1)?,
                size: row.get(2)?,
                created_at: row.get(3)?,
                path: row.get(4)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("query media rows for owner")?;
    Ok(rows)
}

/// One page of an Owner's stored media hashes, `hash ASC`, keyset-paged
/// (`hash > after`). Hashes are unique per Owner, so the hash itself is the
/// cursor.
pub fn hashes_page(
    conn: &Connection,
    pubkey: &[u8],
    after: Option<&str>,
    limit: i64,
) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "SELECT hash FROM served_media
         WHERE pubkey = ?1 AND (?2 IS NULL OR hash > ?2)
         ORDER BY hash ASC
         LIMIT ?3",
    )?;
    let rows = stmt
        .query_map(params![pubkey, after, limit], |row| row.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("query media hashes page")?;
    Ok(rows)
}

/// Total bytes stored for an Owner (for cap enforcement).
pub fn total_bytes(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COALESCE(SUM(size), 0) FROM served_media WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("sum served_media size")
}
