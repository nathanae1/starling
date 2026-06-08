//! The relay supervisor: owns the [`ArtiNode`], launches one onion +
//! axum task per paired Owner, and implements [`RelayControl`] for the
//! admin `/pair` and unpair flows.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use starling_arti::{ArtiNode, OnionHandle};
use starling_relay_admin::RelayControl;
use starling_relay_http::{owner_router, Caps, OwnerCtx};
use starling_relay_storage::{owners, Db, PairedOwner};
use starling_wire::pairing::relay_id;
use tokio::net::TcpListener;
use tokio::sync::{oneshot, Mutex};

/// A running Owner: its onion (drop = unpublish) and its axum serving task.
struct OwnerTask {
    _onion: OnionHandle,
    shutdown: Option<oneshot::Sender<()>>,
    join: tokio::task::JoinHandle<()>,
}

pub struct Supervisor {
    db: Db,
    arti: Arc<ArtiNode>,
    media_dir: PathBuf,
    caps: Caps,
    admin_onion: String,
    port_range: (u16, u16),
    owners: Mutex<HashMap<[u8; 32], OwnerTask>>,
    /// Serializes port allocation + insert so two concurrent pairings can't
    /// pick the same loopback port.
    pair_lock: Mutex<()>,
}

impl Supervisor {
    pub fn new(
        db: Db,
        arti: Arc<ArtiNode>,
        media_dir: PathBuf,
        caps: Caps,
        admin_onion: String,
        port_range: (u16, u16),
    ) -> Self {
        Supervisor {
            db,
            arti,
            media_dir,
            caps,
            admin_onion,
            port_range,
            owners: Mutex::new(HashMap::new()),
            pair_lock: Mutex::new(()),
        }
    }

    /// On boot, relaunch the onion + serving task for every persisted Owner.
    /// Launches sequentially to avoid stampeding the Tor descriptor upload.
    pub async fn restore_all(&self) -> Result<()> {
        let rows = {
            let conn = self.db.get()?;
            owners::list(&conn)?
        };
        for row in rows {
            let pubkey = to_pubkey(&row.pubkey)?;
            if let Err(e) = self.launch_owner(pubkey, row.local_port).await {
                log::error!(
                    "failed to restore owner {}: {e:?}",
                    hex::encode(&row.pubkey[..4])
                );
            } else {
                log::info!(
                    "restored owner {} on {} (port {})",
                    hex::encode(&row.pubkey[..4]),
                    row.relay_onion_address,
                    row.local_port
                );
            }
        }
        Ok(())
    }

    /// Launch the per-Owner onion + axum task. Returns the onion address.
    async fn launch_owner(&self, pubkey: [u8; 32], port: u16) -> Result<String> {
        let nickname = hex::encode(pubkey);
        let onion = self
            .arti
            .launch_service(&nickname, port)
            .with_context(|| format!("launch onion for {nickname}"))?;
        let address = onion.address().to_string();

        let ctx = OwnerCtx {
            db: self.db.clone(),
            owner_pubkey: pubkey,
            media_dir: self.media_dir.clone(),
            caps: self.caps,
        };
        let listener = TcpListener::bind(("127.0.0.1", port))
            .await
            .with_context(|| format!("bind owner router on 127.0.0.1:{port}"))?;
        let (tx, rx) = oneshot::channel::<()>();
        let join = tokio::spawn(async move {
            let server = axum::serve(listener, owner_router(ctx))
                .with_graceful_shutdown(async {
                    rx.await.ok();
                });
            if let Err(e) = server.await {
                log::error!("owner router on :{port} exited: {e}");
            }
        });

        self.owners.lock().await.insert(
            pubkey,
            OwnerTask {
                _onion: onion,
                shutdown: Some(tx),
                join,
            },
        );
        Ok(address)
    }
}

#[async_trait::async_trait]
impl RelayControl for Supervisor {
    fn admin_onion(&self) -> String {
        self.admin_onion.clone()
    }

    async fn pair_owner(
        &self,
        owner_pubkey: [u8; 32],
        label: Option<String>,
    ) -> Result<(String, String)> {
        // Already paired? Return the existing onion (idempotent re-pair).
        {
            let conn = self.db.get()?;
            if let Some(existing) = owners::get(&conn, &owner_pubkey)? {
                let rid = relay_id(&owner_pubkey, &existing.relay_onion_address);
                return Ok((existing.relay_onion_address, rid));
            }
        }

        let _guard = self.pair_lock.lock().await;

        // Allocate the lowest free loopback port.
        let port = {
            let conn = self.db.get()?;
            let used = owners::used_ports(&conn)?;
            owners::lowest_free_port(self.port_range.0, self.port_range.1, &used)
                .ok_or_else(|| anyhow!("no free loopback ports in range"))?
        };

        // Launch onion + serving task; this is the slow step (~30s).
        let relay_onion = self.launch_owner(owner_pubkey, port).await?;
        let rid = relay_id(&owner_pubkey, &relay_onion);

        // Persist. If this fails, tear the freshly-launched task back down.
        let insert = {
            let conn = self.db.get()?;
            owners::insert(
                &conn,
                &PairedOwner {
                    pubkey: owner_pubkey.to_vec(),
                    label,
                    paired_at: now_secs(),
                    relay_onion_address: relay_onion.clone(),
                    local_port: port,
                    storage_cap_bytes: None,
                },
            )
        };
        if let Err(e) = insert {
            self.stop_owner(owner_pubkey).await;
            return Err(e.context("persist paired_owner"));
        }

        log::info!(
            "paired owner {} → {} (port {})",
            hex::encode(&owner_pubkey[..4]),
            relay_onion,
            port
        );
        Ok((relay_onion, rid))
    }

    async fn unpair_owner(&self, owner_pubkey: [u8; 32]) -> Result<()> {
        self.stop_owner(owner_pubkey).await;
        let conn = self.db.get()?;
        owners::delete(&conn, &owner_pubkey)?;
        // NOTE (v1): the onion is unpublished (handle dropped) but its HS
        // keypair remains on disk under arti's keystore. Erasing it via
        // tor-keymgr is a follow-up (Plan 15 M5 spike); the orphaned key is
        // inert.
        log::info!("unpaired owner {}", hex::encode(&owner_pubkey[..4]));
        Ok(())
    }
}

impl Supervisor {
    /// Stop + remove an Owner's serving task and unpublish its onion.
    async fn stop_owner(&self, pubkey: [u8; 32]) {
        if let Some(mut task) = self.owners.lock().await.remove(&pubkey) {
            if let Some(tx) = task.shutdown.take() {
                let _ = tx.send(());
            }
            task.join.abort();
            // `_onion` drops here → Arti unpublishes the descriptor.
        }
    }

    /// Graceful shutdown of all Owner tasks (SIGTERM path).
    pub async fn shutdown_all(&self) {
        let mut owners = self.owners.lock().await;
        for (_pk, mut task) in owners.drain() {
            if let Some(tx) = task.shutdown.take() {
                let _ = tx.send(());
            }
            task.join.abort();
        }
    }
}

fn to_pubkey(bytes: &[u8]) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow!("stored pubkey is not 32 bytes"))
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
