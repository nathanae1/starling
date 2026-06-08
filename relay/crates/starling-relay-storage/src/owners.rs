//! `paired_owners` DAO + loopback-port allocation.

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone)]
pub struct PairedOwner {
    pub pubkey: Vec<u8>,
    pub label: Option<String>,
    pub paired_at: i64,
    pub relay_onion_address: String,
    pub local_port: u16,
    pub storage_cap_bytes: Option<i64>,
}

fn row_to_owner(row: &rusqlite::Row) -> rusqlite::Result<PairedOwner> {
    Ok(PairedOwner {
        pubkey: row.get(0)?,
        label: row.get(1)?,
        paired_at: row.get(2)?,
        relay_onion_address: row.get(3)?,
        local_port: row.get::<_, i64>(4)? as u16,
        storage_cap_bytes: row.get(5)?,
    })
}

pub fn insert(conn: &Connection, owner: &PairedOwner) -> Result<()> {
    conn.execute(
        "INSERT INTO paired_owners
            (pubkey, label, paired_at, relay_onion_address, local_port, storage_cap_bytes)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            owner.pubkey,
            owner.label,
            owner.paired_at,
            owner.relay_onion_address,
            owner.local_port as i64,
            owner.storage_cap_bytes,
        ],
    )
    .context("insert paired_owner")?;
    Ok(())
}

pub fn get(conn: &Connection, pubkey: &[u8]) -> Result<Option<PairedOwner>> {
    conn.query_row(
        "SELECT pubkey, label, paired_at, relay_onion_address, local_port, storage_cap_bytes
         FROM paired_owners WHERE pubkey = ?1",
        params![pubkey],
        row_to_owner,
    )
    .optional()
    .context("get paired_owner")
}

pub fn list(conn: &Connection) -> Result<Vec<PairedOwner>> {
    let mut stmt = conn.prepare(
        "SELECT pubkey, label, paired_at, relay_onion_address, local_port, storage_cap_bytes
         FROM paired_owners ORDER BY paired_at ASC",
    )?;
    let rows = stmt
        .query_map([], row_to_owner)?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("list paired_owners")?;
    Ok(rows)
}

/// Delete an Owner and (via ON DELETE CASCADE) all their served events and
/// media rows. Returns the number of owner rows removed (0 or 1).
pub fn delete(conn: &Connection, pubkey: &[u8]) -> Result<usize> {
    let n = conn
        .execute("DELETE FROM paired_owners WHERE pubkey = ?1", params![pubkey])
        .context("delete paired_owner")?;
    Ok(n)
}

/// The set of loopback ports already assigned to Owners.
pub fn used_ports(conn: &Connection) -> Result<Vec<u16>> {
    let mut stmt = conn.prepare("SELECT local_port FROM paired_owners")?;
    let ports = stmt
        .query_map([], |row| Ok(row.get::<_, i64>(0)? as u16))?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("query used ports")?;
    Ok(ports)
}

/// Lowest free port in `[lo, hi]` not present in `used`. `None` if the
/// range is exhausted.
pub fn lowest_free_port(lo: u16, hi: u16, used: &[u16]) -> Option<u16> {
    (lo..=hi).find(|p| !used.contains(p))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lowest_free_port_skips_used() {
        assert_eq!(lowest_free_port(17000, 17999, &[17000, 17001]), Some(17002));
        assert_eq!(lowest_free_port(17000, 17000, &[17000]), None);
        assert_eq!(lowest_free_port(17000, 17999, &[]), Some(17000));
    }
}
