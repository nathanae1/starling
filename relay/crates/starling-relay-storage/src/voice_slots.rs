//! `voice_slots` DAO: the blinded room-slot registry for SFU voice
//! (Plan 20). The phone pushes the owner's **complete** slot set
//! (replace-the-set semantics); the live in-memory registry inside
//! `starling-relay-voice` mirrors these rows.

use anyhow::{Context, Result};
use rusqlite::{params, Connection};

#[derive(Debug, Clone)]
pub struct VoiceSlot {
    pub pubkey: Vec<u8>,
    /// `BLAKE2b-256(voiceToken)` — 32 bytes.
    pub token_hash: Vec<u8>,
    /// Optional per-room cap; effective cap is `min(this, relay max)`.
    pub max_participants: Option<u16>,
    pub updated_at: i64,
}

fn row_to_slot(row: &rusqlite::Row) -> rusqlite::Result<VoiceSlot> {
    Ok(VoiceSlot {
        pubkey: row.get(0)?,
        token_hash: row.get(1)?,
        max_participants: row.get::<_, Option<i64>>(2)?.map(|v| v as u16),
        updated_at: row.get(3)?,
    })
}

/// Replace `pubkey`'s full slot set: delete-then-insert. Callers wrap this
/// in an `immediate_tx` so a concurrent push can't interleave.
pub fn replace_set(
    conn: &Connection,
    pubkey: &[u8],
    slots: &[(Vec<u8>, Option<u16>)],
    now: i64,
) -> Result<()> {
    conn.execute("DELETE FROM voice_slots WHERE pubkey = ?1", params![pubkey])
        .context("delete voice_slots for owner")?;
    let mut stmt = conn
        .prepare(
            "INSERT INTO voice_slots (pubkey, token_hash, max_participants, updated_at)
             VALUES (?1, ?2, ?3, ?4)",
        )
        .context("prepare voice_slots insert")?;
    for (token_hash, max_participants) in slots {
        stmt.execute(params![
            pubkey,
            token_hash,
            max_participants.map(|v| v as i64),
            now,
        ])
        .context("insert voice_slot")?;
    }
    Ok(())
}

pub fn list_for_owner(conn: &Connection, pubkey: &[u8]) -> Result<Vec<VoiceSlot>> {
    let mut stmt = conn.prepare(
        "SELECT pubkey, token_hash, max_participants, updated_at
         FROM voice_slots WHERE pubkey = ?1 ORDER BY token_hash ASC",
    )?;
    let rows = stmt
        .query_map(params![pubkey], row_to_slot)?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("list voice_slots for owner")?;
    Ok(rows)
}

pub fn count_for_owner(conn: &Connection, pubkey: &[u8]) -> Result<i64> {
    conn.query_row(
        "SELECT COUNT(*) FROM voice_slots WHERE pubkey = ?1",
        params![pubkey],
        |row| row.get(0),
    )
    .context("count voice_slots for owner")
}

/// Every slot on the relay — the boot-time load for the live registry.
pub fn list_all(conn: &Connection) -> Result<Vec<VoiceSlot>> {
    let mut stmt = conn.prepare(
        "SELECT pubkey, token_hash, max_participants, updated_at
         FROM voice_slots ORDER BY pubkey ASC, token_hash ASC",
    )?;
    let rows = stmt
        .query_map([], row_to_slot)?
        .collect::<rusqlite::Result<Vec<_>>>()
        .context("list all voice_slots")?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{owners, owners::PairedOwner, Db};

    fn owner(pubkey: [u8; 32], port: u16) -> PairedOwner {
        PairedOwner {
            pubkey: pubkey.to_vec(),
            label: None,
            paired_at: 1,
            relay_onion_address: "x.onion".into(),
            local_port: port,
            storage_cap_bytes: None,
        }
    }

    #[test]
    fn replace_set_is_per_owner() {
        let db = Db::open_in_memory().unwrap();
        let conn = db.get().unwrap();
        owners::insert(&conn, &owner([1; 32], 17000)).unwrap();
        owners::insert(&conn, &owner([2; 32], 17001)).unwrap();

        replace_set(&conn, &[1; 32], &[(vec![0xaa; 32], Some(8)), (vec![0xbb; 32], None)], 10)
            .unwrap();
        replace_set(&conn, &[2; 32], &[(vec![0xcc; 32], None)], 10).unwrap();
        assert_eq!(count_for_owner(&conn, &[1; 32]).unwrap(), 2);

        // Replacing owner 1's set leaves owner 2 untouched.
        replace_set(&conn, &[1; 32], &[(vec![0xdd; 32], Some(4))], 20).unwrap();
        let slots = list_for_owner(&conn, &[1; 32]).unwrap();
        assert_eq!(slots.len(), 1);
        assert_eq!(slots[0].token_hash, vec![0xdd; 32]);
        assert_eq!(slots[0].max_participants, Some(4));
        assert_eq!(slots[0].updated_at, 20);
        assert_eq!(count_for_owner(&conn, &[2; 32]).unwrap(), 1);

        // Empty set clears everything (all rooms deleted).
        replace_set(&conn, &[1; 32], &[], 30).unwrap();
        assert_eq!(count_for_owner(&conn, &[1; 32]).unwrap(), 0);
    }

    #[test]
    fn owner_delete_cascades_slots() {
        let db = Db::open_in_memory().unwrap();
        let conn = db.get().unwrap();
        owners::insert(&conn, &owner([1; 32], 17000)).unwrap();
        replace_set(&conn, &[1; 32], &[(vec![0xaa; 32], None)], 10).unwrap();

        owners::delete(&conn, &[1; 32]).unwrap();
        assert_eq!(count_for_owner(&conn, &[1; 32]).unwrap(), 0);
    }

    #[test]
    fn slot_push_requires_paired_owner() {
        let db = Db::open_in_memory().unwrap();
        let conn = db.get().unwrap();
        // FK: no paired_owners row → insert must fail.
        assert!(replace_set(&conn, &[9; 32], &[(vec![0xaa; 32], None)], 10).is_err());
    }

    #[test]
    fn list_all_spans_owners() {
        let db = Db::open_in_memory().unwrap();
        let conn = db.get().unwrap();
        owners::insert(&conn, &owner([1; 32], 17000)).unwrap();
        owners::insert(&conn, &owner([2; 32], 17001)).unwrap();
        replace_set(&conn, &[1; 32], &[(vec![0xaa; 32], None)], 10).unwrap();
        replace_set(&conn, &[2; 32], &[(vec![0xbb; 32], Some(6))], 10).unwrap();

        let all = list_all(&conn).unwrap();
        assert_eq!(all.len(), 2);
    }
}
