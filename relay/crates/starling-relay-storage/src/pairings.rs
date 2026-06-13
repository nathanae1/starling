//! `pending_pairings` DAO — short-lived single-use pairing tokens.

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone)]
pub struct PendingPairing {
    pub token: Vec<u8>,
    pub created_at: i64,
    pub expires_at: i64,
    pub consumed_at: Option<i64>,
    pub created_by: String,
    pub label: Option<String>,
}

pub fn insert(conn: &Connection, p: &PendingPairing) -> Result<()> {
    conn.execute(
        "INSERT INTO pending_pairings
            (token, created_at, expires_at, consumed_at, created_by, label)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            p.token,
            p.created_at,
            p.expires_at,
            p.consumed_at,
            p.created_by,
            p.label
        ],
    )
    .context("insert pending_pairing")?;
    Ok(())
}

pub fn get(conn: &Connection, token: &[u8]) -> Result<Option<PendingPairing>> {
    conn.query_row(
        "SELECT token, created_at, expires_at, consumed_at, created_by, label
         FROM pending_pairings WHERE token = ?1",
        params![token],
        |row| {
            Ok(PendingPairing {
                token: row.get(0)?,
                created_at: row.get(1)?,
                expires_at: row.get(2)?,
                consumed_at: row.get(3)?,
                created_by: row.get(4)?,
                label: row.get(5)?,
            })
        },
    )
    .optional()
    .context("get pending_pairing")
}

/// Mark a token consumed. Returns the number of rows updated; the caller
/// can treat 0 as "already consumed / unknown".
pub fn mark_consumed(conn: &Connection, token: &[u8], at: i64) -> Result<usize> {
    let n = conn
        .execute(
            "UPDATE pending_pairings SET consumed_at = ?2
             WHERE token = ?1 AND consumed_at IS NULL",
            params![token, at],
        )
        .context("mark pending_pairing consumed")?;
    Ok(n)
}

/// Consume every still-unconsumed token. Minting a new token invalidates
/// all prior ones (exactly-one-active-token semantics), so a photographed
/// QR stops being claimable as soon as the `/pair` page re-mints.
pub fn consume_all_unconsumed(conn: &Connection, at: i64) -> Result<usize> {
    let n = conn
        .execute(
            "UPDATE pending_pairings SET consumed_at = ?1
             WHERE consumed_at IS NULL",
            params![at],
        )
        .context("consume all unconsumed pairings")?;
    Ok(n)
}

/// Delete tokens that expired before `now`.
pub fn prune_expired(conn: &Connection, now: i64) -> Result<usize> {
    let n = conn
        .execute(
            "DELETE FROM pending_pairings WHERE expires_at < ?1",
            params![now],
        )
        .context("prune expired pairings")?;
    Ok(n)
}
