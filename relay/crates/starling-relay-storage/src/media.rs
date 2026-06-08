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

/// Total bytes stored for an Owner (for cap enforcement).
pub fn total_bytes(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COALESCE(SUM(size), 0) FROM served_media WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("sum served_media size")
}
