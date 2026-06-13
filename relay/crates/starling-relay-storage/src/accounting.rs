//! Storage-cap accounting — the single chokepoint both `POST /events` and
//! `POST /media` call before writing (D4). Usage counts event payload bytes
//! and media blob bytes combined; `0` for either cap means unlimited.

use anyhow::Result;
use rusqlite::Connection;

use crate::{events, media};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CapCheck {
    Ok,
    OwnerExceeded,
    HostExceeded,
}

/// Bytes stored for one Owner: event payloads + media blobs.
pub fn owner_usage(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    Ok(events::total_bytes(conn, pubkey)? + media::total_bytes(conn, pubkey)?)
}

/// Bytes stored across all Owners.
pub fn host_usage(conn: &Connection) -> Result<i64> {
    let events: i64 = conn.query_row(
        "SELECT COALESCE(SUM(size), 0) FROM served_events",
        [],
        |row| row.get(0),
    )?;
    let media: i64 = conn.query_row(
        "SELECT COALESCE(SUM(size), 0) FROM served_media",
        [],
        |row| row.get(0),
    )?;
    Ok(events + media)
}

/// Would storing `incoming` more bytes for `pubkey` bust the Owner's cap or
/// the host-wide disk cap?
pub fn check_capacity(
    conn: &Connection,
    pubkey: &[u8],
    incoming: i64,
    owner_cap: i64,
    disk_cap: i64,
) -> Result<CapCheck> {
    if owner_cap > 0 && owner_usage(conn, pubkey)? + incoming > owner_cap {
        return Ok(CapCheck::OwnerExceeded);
    }
    if disk_cap > 0 && host_usage(conn)? + incoming > disk_cap {
        return Ok(CapCheck::HostExceeded);
    }
    Ok(CapCheck::Ok)
}
