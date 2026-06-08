//! `admin_credentials` DAO — single-row argon2id password hash for the
//! optional LAN-exposed admin UI.

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone)]
pub struct AdminCreds {
    pub password_hash: String,
    pub updated_at: i64,
}

pub fn get(conn: &Connection) -> Result<Option<AdminCreds>> {
    conn.query_row(
        "SELECT password_hash, updated_at FROM admin_credentials WHERE id = 1",
        [],
        |row| {
            Ok(AdminCreds {
                password_hash: row.get(0)?,
                updated_at: row.get(1)?,
            })
        },
    )
    .optional()
    .context("get admin_credentials")
}

/// Upsert the single credentials row.
pub fn set(conn: &Connection, password_hash: &str, updated_at: i64) -> Result<()> {
    conn.execute(
        "INSERT INTO admin_credentials (id, password_hash, updated_at)
         VALUES (1, ?1, ?2)
         ON CONFLICT(id) DO UPDATE SET password_hash = ?1, updated_at = ?2",
        params![password_hash, updated_at],
    )
    .context("set admin_credentials")?;
    Ok(())
}
