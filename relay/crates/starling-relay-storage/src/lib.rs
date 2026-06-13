//! SQLite storage for the relay. One `r2d2` pool; every connection is
//! initialized with WAL + foreign-key enforcement. DAOs are plain functions
//! over a `&rusqlite::Connection` so callers can run several in one
//! transaction (the pairing path needs port-allocation + insert atomic).

use std::path::Path;

use anyhow::{Context, Result};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;

pub mod accounting;
pub mod creds;
pub mod events;
pub mod media;
pub mod owners;
pub mod pairings;

pub use creds::AdminCreds;
pub use events::ServedEvent;
pub use rusqlite::Connection;
pub use media::ServedMedia;
pub use owners::PairedOwner;
pub use pairings::PendingPairing;

const MIGRATION_0001: &str = include_str!("../migrations/0001_init.sql");
const MIGRATION_0002: &str = include_str!("../migrations/0002_event_size.sql");

pub type PooledConn = r2d2::PooledConnection<SqliteConnectionManager>;

#[derive(Clone)]
pub struct Db {
    pool: Pool<SqliteConnectionManager>,
}

impl Db {
    /// Open (creating if needed) the relay database at `path` and run
    /// migrations.
    pub fn open(path: &Path) -> Result<Self> {
        let manager = SqliteConnectionManager::file(path).with_init(|c| {
            c.execute_batch(
                "PRAGMA journal_mode=WAL;\
                 PRAGMA synchronous=NORMAL;\
                 PRAGMA busy_timeout=5000;\
                 PRAGMA foreign_keys=ON;",
            )
        });
        let pool = Pool::builder()
            .build(manager)
            .context("build sqlite connection pool")?;
        let db = Db { pool };
        db.migrate()?;
        Ok(db)
    }

    /// In-memory database for tests. Uses a single connection (pool size 1)
    /// so the shared `:memory:` database survives across `get()` calls.
    pub fn open_in_memory() -> Result<Self> {
        let manager = SqliteConnectionManager::memory().with_init(|c| {
            c.execute_batch("PRAGMA foreign_keys=ON;")
        });
        let pool = Pool::builder()
            .max_size(1)
            .build(manager)
            .context("build in-memory sqlite pool")?;
        let db = Db { pool };
        db.migrate()?;
        Ok(db)
    }

    pub fn get(&self) -> Result<PooledConn> {
        self.pool.get().context("acquire pooled connection")
    }

    /// Run a blocking DB closure on the tokio blocking pool. All async code
    /// (route handlers, middleware) must use this instead of `get()` — a
    /// pool checkout (up to 30s) or a busy SQLite write would otherwise park
    /// a runtime worker. Never call while already holding a [`PooledConn`]:
    /// the in-memory test pool has a single connection.
    pub async fn run<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&rusqlite::Connection) -> Result<T> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.clone();
        tokio::task::spawn_blocking(move || {
            let conn = pool.get().context("acquire pooled connection")?;
            f(&conn)
        })
        .await
        .context("join blocking db task")?
    }

    fn migrate(&self) -> Result<()> {
        let conn = self.get()?;
        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .context("read user_version")?;
        // Pre-versioning DBs report 0 with the 0001 tables already present;
        // 0001 is IF-NOT-EXISTS throughout, so re-running it is harmless.
        if version < 1 {
            conn.execute_batch(MIGRATION_0001)
                .context("run migration 0001")?;
        }
        if version < 2 {
            conn.execute_batch(MIGRATION_0002)
                .context("run migration 0002")?;
        }
        conn.execute_batch("PRAGMA user_version = 2")
            .context("set user_version")?;
        Ok(())
    }
}
