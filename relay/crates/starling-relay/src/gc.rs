//! Startup media-directory GC: reconcile the `served_media` table with the
//! files actually on disk.
//!
//! Runs from `serve()` BEFORE `Supervisor::restore_all()` — no serving
//! router exists yet, so nothing can write media concurrently and the
//! sweep needs no locking. Three legs, each healing one crash window:
//!
//! 1. **Unknown-owner dirs** — an unpair that crashed after the DB delete
//!    but before `remove_dir_all` leaves the whole namespace dir behind.
//! 2. **Orphan files** — a `POST /media` crash between the tmp write and
//!    the row insert, a `.tmp` the rename never claimed, or a delete that
//!    committed its row removal but died before the unlink.
//! 3. **Phantom rows** — a row whose file is gone (torn disk, manual
//!    cleanup). Dropping the row frees the bytes it pinned in the cap
//!    accounting, and the hash leaves `/media-manifest`, so the phone's
//!    reconcile re-pushes the blob — today's 404-forever becomes
//!    self-healing.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use anyhow::Result;
use starling_relay_storage::{media, owners, Db};

#[derive(Debug, Default, PartialEq)]
pub struct GcStats {
    pub unknown_owner_dirs_removed: usize,
    pub orphan_files_removed: usize,
    pub phantom_rows_removed: usize,
}

/// Sweep `media_dir` against the database. Filesystem errors on individual
/// entries are logged and skipped — GC must never stop the relay from
/// booting.
pub fn sweep(db: &Db, media_dir: &Path) -> Result<GcStats> {
    let mut stats = GcStats::default();
    let conn = db.get()?;

    let owner_rows = owners::list(&conn)?;
    let known_dirs: HashSet<String> = owner_rows.iter().map(|o| hex::encode(&o.pubkey)).collect();

    // Leg 1: remove top-level dirs that belong to no paired Owner.
    for entry in read_dir_or_empty(media_dir) {
        let name = entry.file_name().to_string_lossy().into_owned();
        if known_dirs.contains(&name) {
            continue;
        }
        let path = entry.path();
        if path.is_dir() {
            match std::fs::remove_dir_all(&path) {
                Ok(()) => stats.unknown_owner_dirs_removed += 1,
                Err(e) => log::warn!("gc: could not remove unknown dir {name}: {e}"),
            }
        }
    }

    // Legs 2 + 3, per Owner.
    for owner in &owner_rows {
        let owner_hex = hex::encode(&owner.pubkey);
        let rows = media::rows_for_owner(&conn, &owner.pubkey)?;
        let expected: HashSet<PathBuf> = rows.iter().map(|r| media_dir.join(&r.path)).collect();

        // Leg 2: unlink files (including stray `.tmp`s) with no row.
        let owner_dir = media_dir.join(&owner_hex);
        for file in walk_files(&owner_dir) {
            if expected.contains(&file) {
                continue;
            }
            match std::fs::remove_file(&file) {
                Ok(()) => stats.orphan_files_removed += 1,
                Err(e) => log::warn!("gc: could not unlink {}: {e}", file.display()),
            }
        }

        // Leg 3: drop rows whose file is missing.
        for row in rows {
            if media_dir.join(&row.path).exists() {
                continue;
            }
            media::delete(&conn, &owner.pubkey, &row.hash)?;
            stats.phantom_rows_removed += 1;
        }
    }

    if stats != GcStats::default() {
        log::info!(
            "media gc: removed {} unknown-owner dir(s), {} orphan file(s), {} phantom row(s)",
            stats.unknown_owner_dirs_removed,
            stats.orphan_files_removed,
            stats.phantom_rows_removed,
        );
    }
    Ok(stats)
}

/// `read_dir` that treats a missing/unreadable dir as empty (first boot has
/// no media dir yet).
fn read_dir_or_empty(dir: &Path) -> Vec<std::fs::DirEntry> {
    match std::fs::read_dir(dir) {
        Ok(entries) => entries.filter_map(|e| e.ok()).collect(),
        Err(_) => Vec::new(),
    }
}

/// All regular files under `dir`, recursively.
fn walk_files(dir: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in read_dir_or_empty(&d) {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else {
                files.push(path);
            }
        }
    }
    files
}

#[cfg(test)]
mod tests {
    use super::*;
    use starling_relay_storage::{owners, PairedOwner, ServedMedia};

    fn owner(db: &Db, seed: u8) -> [u8; 32] {
        let pubkey = [seed; 32];
        let conn = db.get().unwrap();
        owners::insert(
            &conn,
            &PairedOwner {
                pubkey: pubkey.to_vec(),
                label: None,
                paired_at: 1,
                relay_onion_address: format!("owner{seed}.onion"),
                local_port: 17000 + seed as u16,
                storage_cap_bytes: None,
            },
        )
        .unwrap();
        pubkey
    }

    fn insert_media(db: &Db, pubkey: &[u8; 32], hash: &str, rel: &str, size: i64) {
        let conn = db.get().unwrap();
        media::insert(
            &conn,
            &ServedMedia {
                pubkey: pubkey.to_vec(),
                hash: hash.to_string(),
                size,
                created_at: 1,
                path: rel.to_string(),
            },
        )
        .unwrap();
    }

    fn write_file(root: &Path, rel: &str, bytes: &[u8]) -> PathBuf {
        let full = root.join(rel);
        std::fs::create_dir_all(full.parent().unwrap()).unwrap();
        std::fs::write(&full, bytes).unwrap();
        full
    }

    /// A file with no `served_media` row (crashed push, unclaimed `.tmp`,
    /// or post-commit delete crash) is unlinked; a filed row survives.
    #[test]
    fn orphan_files_are_unlinked() {
        let db = Db::open_in_memory().unwrap();
        let media_dir = tempfile::tempdir().unwrap();
        let pk = owner(&db, 3);
        let hex_pk = hex::encode(pk);

        let hash = "a".repeat(64);
        let rel = format!("{hex_pk}/aa/aaaa/{hash}");
        let kept = write_file(media_dir.path(), &rel, b"blob");
        insert_media(&db, &pk, &hash, &rel, 4);

        let orphan = write_file(media_dir.path(), &format!("{hex_pk}/bb/bbbb/{}", "b".repeat(64)), b"x");
        let tmp = write_file(media_dir.path(), &format!("{hex_pk}/aa/aaaa/{hash}.tmp"), b"torn");

        let stats = sweep(&db, media_dir.path()).unwrap();
        assert_eq!(stats.orphan_files_removed, 2);
        assert!(kept.exists());
        assert!(!orphan.exists());
        assert!(!tmp.exists());
    }

    /// A whole namespace dir belonging to no paired Owner (unpair crashed
    /// between the DB delete and `remove_dir_all`) goes away.
    #[test]
    fn unknown_owner_dir_is_removed() {
        let db = Db::open_in_memory().unwrap();
        let media_dir = tempfile::tempdir().unwrap();
        let pk = owner(&db, 3);
        let hex_pk = hex::encode(pk);

        let hash = "a".repeat(64);
        let rel = format!("{hex_pk}/aa/aaaa/{hash}");
        let kept = write_file(media_dir.path(), &rel, b"blob");
        insert_media(&db, &pk, &hash, &rel, 4);

        let ghost = hex::encode([9u8; 32]);
        write_file(media_dir.path(), &format!("{ghost}/cc/cccc/{}", "c".repeat(64)), b"y");

        let stats = sweep(&db, media_dir.path()).unwrap();
        assert_eq!(stats.unknown_owner_dirs_removed, 1);
        assert!(!media_dir.path().join(&ghost).exists());
        assert!(kept.exists());
    }

    /// A row whose file vanished is dropped, freeing its phantom
    /// accounting bytes so the hash leaves `/media-manifest` and the phone
    /// re-pushes it.
    #[test]
    fn phantom_row_is_dropped() {
        let db = Db::open_in_memory().unwrap();
        let media_dir = tempfile::tempdir().unwrap();
        let pk = owner(&db, 3);
        let hex_pk = hex::encode(pk);

        let hash = "d".repeat(64);
        insert_media(&db, &pk, &hash, &format!("{hex_pk}/dd/dddd/{hash}"), 512);

        let stats = sweep(&db, media_dir.path()).unwrap();
        assert_eq!(stats.phantom_rows_removed, 1);
        let conn = db.get().unwrap();
        assert!(media::get(&conn, &pk, &hash).unwrap().is_none());
        assert_eq!(media::total_bytes(&conn, &pk).unwrap(), 0);
    }

    /// First boot: no media dir at all — sweep is a no-op, not an error.
    #[test]
    fn missing_media_dir_is_fine() {
        let db = Db::open_in_memory().unwrap();
        let stats = sweep(&db, Path::new("/nonexistent/starling-gc-test")).unwrap();
        assert_eq!(stats, GcStats::default());
    }
}
