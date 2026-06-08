//! SQLite storage for the relay. One `r2d2` pool; every connection is
//! initialized with WAL + foreign-key enforcement. DAOs are plain functions
//! over a `&rusqlite::Connection` so callers can run several in one
//! transaction (the pairing path needs port-allocation + insert atomic).

use std::path::Path;

use anyhow::{Context, Result};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;

pub mod creds;
pub mod events;
pub mod media;
pub mod owners;
pub mod pairings;

pub use creds::AdminCreds;
pub use events::ServedEvent;
pub use media::ServedMedia;
pub use owners::PairedOwner;
pub use pairings::PendingPairing;

const MIGRATION_0001: &str = include_str!("../migrations/0001_init.sql");

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

    fn migrate(&self) -> Result<()> {
        let conn = self.get()?;
        conn.execute_batch(MIGRATION_0001)
            .context("run migration 0001")?;
        Ok(())
    }
}
