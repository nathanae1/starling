//! The relay supervisor: owns the [`ArtiNode`], launches one onion +
//! axum task per paired Owner, and implements [`RelayControl`] for the
//! admin `/pair` and unpair flows.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use starling_arti::ArtiNode;
use starling_relay_admin::RelayControl;
use starling_relay_http::{owner_router, Caps, OwnerCtx, SlotRegistrar, UnpairHandle, VoiceCtx};
use starling_relay_storage::{owners, Db, PairedOwner};
use starling_relay_voice::{voice_ws_router, VoiceHandle};
use starling_wire::now_secs;
use starling_wire::pairing::relay_id;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, Mutex};

/// Backoff bounds for the per-Owner serve-loop after an unexpected exit.
const SERVE_BACKOFF_MIN: Duration = Duration::from_millis(500);
const SERVE_BACKOFF_MAX: Duration = Duration::from_secs(30);

/// Delay between a wire `POST /unpair` request and the actual wipe. The
/// wipe aborts the requesting Owner's own serving task, so this grace
/// period lets the 200 response flush first — otherwise every successful
/// wire unpair looks like a transport failure to the phone, which then
/// retries against a dead onion.
const UNPAIR_RESPONSE_GRACE: Duration = Duration::from_millis(500);

/// The one Arti capability the supervisor consumes, as a seam so unit
/// tests can stub Tor away (a real launch needs a bootstrapped network).
pub trait OnionLauncher: Send + Sync {
    fn launch_service(&self, nickname: &str, local_port: u16) -> Result<Box<dyn LaunchedOnion>>;
}

/// A live published onion service; dropping it unpublishes the descriptor.
pub trait LaunchedOnion: Send {
    fn address(&self) -> &str;
}

impl OnionLauncher for ArtiNode {
    fn launch_service(&self, nickname: &str, local_port: u16) -> Result<Box<dyn LaunchedOnion>> {
        Ok(Box::new(ArtiNode::launch_service(self, nickname, local_port)?))
    }
}

impl LaunchedOnion for starling_arti::OnionHandle {
    fn address(&self) -> &str {
        starling_arti::OnionHandle::address(self)
    }
}

/// A running Owner: its onion (drop = unpublish) and its axum serving task.
/// The task self-heals — if the loopback listener dies it rebinds the same
/// port with backoff, so the published onion never ends up pointing at a
/// dead listener (M5). Aborting the task drops the onion with it.
struct OwnerTask {
    _onion: Box<dyn LaunchedOnion>,
    join: tokio::task::JoinHandle<()>,
}

pub struct Supervisor {
    db: Db,
    arti: Arc<dyn OnionLauncher>,
    media_dir: PathBuf,
    caps: Caps,
    admin_onion: String,
    port_range: (u16, u16),
    /// The shared SFU (`(handle, max_participants)`) when `[voice]` is
    /// enabled. One server for all owners; each owner's router gets the
    /// `/ws/voice` route and a slot-registrar hook.
    voice: Option<(VoiceHandle, u16)>,
    owners: Mutex<HashMap<[u8; 32], OwnerTask>>,
    /// Count of Owner tasks currently holding a live listener. Surfaced in
    /// `/health` so a wedged owner (onion up, listener flapping) is visible.
    serving: Arc<AtomicUsize>,
    /// Serializes the whole pair/unpair flow (paired check, port
    /// allocation, launch, insert) so concurrent pairings can't double-
    /// launch one pubkey or pick the same loopback port. Lock order is
    /// always `pair_lock` → `owners`, never the reverse.
    pair_lock: Mutex<()>,
    /// Wire-unpair requests from per-Owner routers (`POST /unpair`, A3).
    /// Routers send; the dispatcher spawned by
    /// [`Supervisor::spawn_unpair_dispatcher`] receives and runs the
    /// normal unpair path after [`UNPAIR_RESPONSE_GRACE`].
    unpair_tx: mpsc::UnboundedSender<[u8; 32]>,
    unpair_rx: std::sync::Mutex<Option<mpsc::UnboundedReceiver<[u8; 32]>>>,
}

/// Increments the serving gauge on creation, decrements on drop — so a task
/// cancelled by `abort()` (unpair/shutdown) still releases its slot.
struct ServingGuard(Arc<AtomicUsize>);
impl ServingGuard {
    fn new(counter: Arc<AtomicUsize>) -> Self {
        counter.fetch_add(1, Ordering::Relaxed);
        ServingGuard(counter)
    }
}
impl Drop for ServingGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

impl Supervisor {
    pub fn new(
        db: Db,
        arti: Arc<dyn OnionLauncher>,
        media_dir: PathBuf,
        caps: Caps,
        admin_onion: String,
        port_range: (u16, u16),
        voice: Option<(VoiceHandle, u16)>,
    ) -> Self {
        let (unpair_tx, unpair_rx) = mpsc::unbounded_channel();
        Supervisor {
            db,
            arti,
            media_dir,
            caps,
            admin_onion,
            port_range,
            voice,
            owners: Mutex::new(HashMap::new()),
            serving: Arc::new(AtomicUsize::new(0)),
            pair_lock: Mutex::new(()),
            unpair_tx,
            unpair_rx: std::sync::Mutex::new(Some(unpair_rx)),
        }
    }

    /// Spawn the task that services wire `POST /unpair` requests: wait out
    /// the response-flush grace, then run the normal unpair path. Call once
    /// after wrapping the supervisor in an `Arc`; later calls are no-ops.
    pub fn spawn_unpair_dispatcher(self: &Arc<Self>) {
        let Some(mut rx) = self.unpair_rx.lock().unwrap().take() else {
            return;
        };
        let sup = Arc::clone(self);
        tokio::spawn(async move {
            while let Some(pubkey) = rx.recv().await {
                tokio::time::sleep(UNPAIR_RESPONSE_GRACE).await;
                match RelayControl::unpair_owner(&*sup, pubkey).await {
                    Ok(()) => log::info!(
                        "wire unpair completed for {}",
                        hex::encode(&pubkey[..4])
                    ),
                    Err(e) => log::error!(
                        "wire unpair failed for {}: {e:?}",
                        hex::encode(&pubkey[..4])
                    ),
                }
            }
        });
    }

    /// (serving, total) owner counts for `/health`.
    pub async fn liveness(&self) -> (usize, usize) {
        let total = self.owners.lock().await.len();
        (self.serving.load(Ordering::Relaxed), total)
    }

    /// On boot, relaunch the onion + serving task for every persisted Owner.
    /// Launches sequentially to avoid stampeding the Tor descriptor upload.
    pub async fn restore_all(&self) -> Result<()> {
        let rows = {
            let conn = self.db.get()?;
            owners::list(&conn)?
        };
        for row in rows {
            // A single corrupt row must not brick the whole relay (L2) —
            // skip-and-log, exactly like a launch failure below.
            let pubkey = match to_pubkey(&row.pubkey) {
                Ok(pk) => pk,
                Err(e) => {
                    log::error!("skipping malformed owner row: {e}");
                    continue;
                }
            };
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

    /// Launch the per-Owner onion + self-healing serving task. Returns the
    /// onion address. The initial listener bind happens here (so a taken
    /// port fails the pair flow fast); subsequent rebinds happen inside the
    /// task's serve-loop.
    async fn launch_owner(&self, pubkey: [u8; 32], port: u16) -> Result<String> {
        let nickname = hex::encode(pubkey);
        let onion = self
            .arti
            .launch_service(&nickname, port)
            .with_context(|| format!("launch onion for {nickname}"))?;
        let address = onion.address().to_string();

        let unpair_tx = self.unpair_tx.clone();
        // Voice: the registrar mirrors owner-signed slot pushes into the
        // live SFU registry (best-effort — the DB row is the durable truth
        // and the registry reloads from it at boot).
        let voice_ctx = self.voice.as_ref().map(|(handle, max_participants)| {
            let handle = handle.clone();
            let registrar: SlotRegistrar = Arc::new(move |slots| {
                let handle = handle.clone();
                tokio::spawn(async move {
                    handle.register_slots(pubkey, slots).await;
                });
            });
            VoiceCtx { max_participants: *max_participants, registrar }
        });
        let ctx = OwnerCtx {
            db: self.db.clone(),
            owner_pubkey: pubkey,
            media_dir: self.media_dir.clone(),
            caps: self.caps,
            // A send can only fail before the dispatcher is spawned or
            // after shutdown; either way dropping the request is correct.
            unpair: Some(Arc::new(move || {
                let _ = unpair_tx.send(pubkey);
            }) as UnpairHandle),
            voice: voice_ctx,
        };
        let voice_handle = self.voice.as_ref().map(|(handle, _)| handle.clone());
        let listener = TcpListener::bind(("127.0.0.1", port))
            .await
            .with_context(|| format!("bind owner router on 127.0.0.1:{port}"))?;

        let serving = self.serving.clone();
        let join = tokio::spawn(async move {
            let _guard = ServingGuard::new(serving);
            let mut listener = Some(listener);
            let mut backoff = SERVE_BACKOFF_MIN;
            loop {
                // First iteration reuses the bind from above; later ones
                // rebind the same port after the previous serve exited.
                let l = match listener.take() {
                    Some(l) => l,
                    None => match TcpListener::bind(("127.0.0.1", port)).await {
                        Ok(l) => {
                            backoff = SERVE_BACKOFF_MIN;
                            l
                        }
                        Err(e) => {
                            log::error!("owner :{port} rebind failed: {e}; retrying in {backoff:?}");
                            tokio::time::sleep(backoff).await;
                            backoff = (backoff * 2).min(SERVE_BACKOFF_MAX);
                            continue;
                        }
                    },
                };
                // Same onion, same URL surface: `/ws/voice` rides the
                // per-owner router. The handler lives in the voice crate —
                // an http→voice dependency would put the DTLS-SRTP tree
                // inside the zero-knowledge dep walk.
                let app = match &voice_handle {
                    Some(handle) => owner_router(ctx.clone())
                        .merge(voice_ws_router(handle.clone(), pubkey)),
                    None => owner_router(ctx.clone()),
                };
                match axum::serve(l, app).await {
                    Ok(()) => {
                        // Graceful return only happens on shutdown wiring we
                        // don't use here; treat as a signal to stop looping.
                        log::info!("owner router on :{port} stopped");
                        break;
                    }
                    Err(e) => {
                        log::error!("owner router on :{port} exited: {e}; relaunching");
                        tokio::time::sleep(backoff).await;
                        backoff = (backoff * 2).min(SERVE_BACKOFF_MAX);
                    }
                }
            }
        });

        self.owners.lock().await.insert(pubkey, OwnerTask { _onion: onion, join });
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
        // The lock comes FIRST: with the already-paired check outside it,
        // two concurrent pairs for one pubkey both proceeded — the second
        // launch overwrote the first's owners-map entry (dropping the live
        // onion), then its insert hit the PK conflict and tore down the
        // replacement, leaving a paired_owners row nothing was serving.
        // Holding it across the ~30s launch (serializing pairings) is
        // intentional.
        let _guard = self.pair_lock.lock().await;

        // Already paired? Return the existing onion (idempotent re-pair) —
        // but only after confirming a task is actually serving it. After a
        // failed restore_all, the row exists with nothing live; the same
        // keystore nickname relaunches the same onion address.
        {
            let conn = self.db.get()?;
            if let Some(existing) = owners::get(&conn, &owner_pubkey)? {
                drop(conn);
                let live = self.owners.lock().await.contains_key(&owner_pubkey);
                if !live {
                    let relaunched = self
                        .launch_owner(owner_pubkey, existing.local_port)
                        .await
                        .context("relaunch dead owner task on re-pair")?;
                    if relaunched != existing.relay_onion_address {
                        // Same nickname → same HS keypair → same address;
                        // anything else means the keystore was wiped.
                        log::warn!(
                            "re-pair of {} relaunched at {} but DB row says {}",
                            hex::encode(&owner_pubkey[..4]),
                            relaunched,
                            existing.relay_onion_address
                        );
                    }
                }
                let rid = relay_id(&owner_pubkey, &existing.relay_onion_address);
                return Ok((existing.relay_onion_address, rid));
            }
        }

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

    async fn liveness(&self) -> Option<(usize, usize)> {
        Some(Supervisor::liveness(self).await)
    }

    async fn voice_overview(&self) -> Option<HashMap<[u8; 32], usize>> {
        match &self.voice {
            Some((handle, _)) => Some(handle.overview().await),
            None => None,
        }
    }

    async fn unpair_owner(&self, owner_pubkey: [u8; 32]) -> Result<()> {
        // Serialize against a concurrent (re-)pair of the same pubkey.
        let _guard = self.pair_lock.lock().await;
        self.stop_owner(owner_pubkey).await;
        // End the owner's live calls and drop their slots from the live
        // registry (the DB rows go via the owner-delete cascade below).
        if let Some((handle, _)) = &self.voice {
            handle.drop_owner(owner_pubkey).await;
        }
        let conn = self.db.get()?;
        owners::delete(&conn, &owner_pubkey)?;
        drop(conn);
        // The DB delete cascades events + media rows; the blob files live
        // under the Owner's namespace dir (S1) and must go too — the admin
        // UI promises "delete all stored data".
        let owner_dir = self.media_dir.join(hex::encode(owner_pubkey));
        let removed = tokio::task::spawn_blocking(move || std::fs::remove_dir_all(&owner_dir))
            .await
            .map_err(anyhow::Error::from)?;
        if let Err(e) = removed {
            if e.kind() != std::io::ErrorKind::NotFound {
                log::warn!(
                    "unpair {}: could not remove media dir: {e}",
                    hex::encode(&owner_pubkey[..4])
                );
            }
        }
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
    /// Awaits the abort so the task's loopback listener is actually closed
    /// on return — an unpair immediately followed by a (re-)pair would
    /// otherwise race the old task for the freed port.
    async fn stop_owner(&self, pubkey: [u8; 32]) {
        let task = self.owners.lock().await.remove(&pubkey);
        if let Some(task) = task {
            task.join.abort();
            let _ = task.join.await;
            // `_onion` drops here → Arti unpublishes the descriptor.
        }
    }

    /// Stop all Owner tasks (SIGTERM path). Aborts and awaits each — the
    /// onions unpublish with the process, so draining in-flight requests
    /// buys nothing, but the awaits make the port release deterministic.
    pub async fn shutdown_all(&self) {
        let drained: Vec<_> = self.owners.lock().await.drain().collect();
        for (_pk, task) in drained {
            task.join.abort();
            let _ = task.join.await;
        }
    }
}

fn to_pubkey(bytes: &[u8]) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow!("stored pubkey is not 32 bytes"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    /// Records launches and flags drops, so tests can assert an onion was
    /// unpublished (handle dropped) without any Tor at all.
    struct StubArti {
        launches: std::sync::Mutex<Vec<(String, u16)>>,
        live: Arc<AtomicUsize>,
    }

    impl StubArti {
        fn new() -> Arc<Self> {
            Arc::new(StubArti {
                launches: std::sync::Mutex::new(Vec::new()),
                live: Arc::new(AtomicUsize::new(0)),
            })
        }
        fn launched(&self) -> Vec<(String, u16)> {
            self.launches.lock().unwrap().clone()
        }
        fn live_onions(&self) -> usize {
            self.live.load(Ordering::SeqCst)
        }
    }

    struct StubOnion {
        address: String,
        live: Arc<AtomicUsize>,
        dropped: Arc<AtomicBool>,
    }
    impl LaunchedOnion for StubOnion {
        fn address(&self) -> &str {
            &self.address
        }
    }
    impl Drop for StubOnion {
        fn drop(&mut self) {
            self.live.fetch_sub(1, Ordering::SeqCst);
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    impl OnionLauncher for StubArti {
        fn launch_service(&self, nickname: &str, port: u16) -> Result<Box<dyn LaunchedOnion>> {
            self.launches.lock().unwrap().push((nickname.to_string(), port));
            self.live.fetch_add(1, Ordering::SeqCst);
            Ok(Box::new(StubOnion {
                // Same nickname → same HS keypair → same address, like Arti.
                address: format!("{nickname}.onion"),
                live: self.live.clone(),
                dropped: Arc::new(AtomicBool::new(false)),
            }))
        }
    }

    fn supervisor(arti: Arc<StubArti>, range: (u16, u16)) -> (Supervisor, Db, tempfile::TempDir) {
        let db = Db::open_in_memory().unwrap();
        let media = tempfile::tempdir().unwrap();
        let sup = Supervisor::new(
            db.clone(),
            arti as Arc<dyn OnionLauncher>,
            media.path().to_path_buf(),
            Caps::default(),
            "admin.onion".into(),
            range,
            None,
        );
        (sup, db, media)
    }

    /// Ports allocate lowest-free and are reclaimed by unpair.
    #[tokio::test]
    async fn pair_allocates_lowest_free_port_and_unpair_reclaims() {
        let arti = StubArti::new();
        // High, narrow range so a busy dev machine can't collide.
        let (sup, _db, _media) = supervisor(arti.clone(), (28910, 28919));

        let (onion_a, _) = sup.pair_owner([1u8; 32], None).await.unwrap();
        let (_onion_b, _) = sup.pair_owner([2u8; 32], None).await.unwrap();
        assert_eq!(
            arti.launched().iter().map(|(_, p)| *p).collect::<Vec<_>>(),
            vec![28910, 28911]
        );
        assert_eq!(onion_a, format!("{}.onion", hex::encode([1u8; 32])));
        assert_eq!(sup.liveness().await.1, 2, "two owners tracked");

        // Unpair A → its port is the lowest free again.
        sup.unpair_owner([1u8; 32]).await.unwrap();
        assert_eq!(sup.liveness().await.1, 1);
        let (_, _) = sup.pair_owner([3u8; 32], None).await.unwrap();
        assert_eq!(arti.launched().last().unwrap().1, 28910);
    }

    /// Re-pairing an already-paired Owner is idempotent while its task is
    /// live (no second launch), and relaunches when the task is NOT live
    /// (the failed-restore / dead-task path).
    #[tokio::test]
    async fn repair_is_idempotent_live_and_relaunches_dead() {
        let arti = StubArti::new();
        let (sup, db, _media) = supervisor(arti.clone(), (28920, 28929));

        let pk = [5u8; 32];
        let (onion_first, rid_first) = sup.pair_owner(pk, None).await.unwrap();
        assert_eq!(arti.launched().len(), 1);

        // Live task → the second pair returns the same identifiers without
        // launching anything.
        let (onion_again, rid_again) = sup.pair_owner(pk, None).await.unwrap();
        assert_eq!(onion_again, onion_first);
        assert_eq!(rid_again, rid_first);
        assert_eq!(arti.launched().len(), 1, "no relaunch while live");

        // Simulate a failed restore: row exists, no live task.
        sup.shutdown_all().await;
        assert_eq!(sup.liveness().await, (0, 0));
        assert_eq!(arti.live_onions(), 0, "shutdown dropped the onion");
        {
            let conn = db.get().unwrap();
            assert!(owners::get(&conn, &pk).unwrap().is_some(), "row survives");
        }
        let (onion_relaunched, _) = sup.pair_owner(pk, None).await.unwrap();
        assert_eq!(onion_relaunched, onion_first, "same nickname, same onion");
        assert_eq!(arti.launched().len(), 2, "dead task relaunched");
        assert_eq!(arti.launched()[1].1, arti.launched()[0].1, "same port");
        assert_eq!(sup.liveness().await.1, 1);
    }

    /// If persisting the paired_owners row fails AFTER the launch, the
    /// freshly-launched task is torn back down and its onion unpublished —
    /// no zombie serving an owner the DB doesn't know.
    #[tokio::test]
    async fn insert_failure_tears_down_fresh_launch() {
        let arti = StubArti::new();
        let (sup, db, _media) = supervisor(arti.clone(), (28930, 28939));
        {
            // Poison the insert (label-triggered) — the only deterministic
            // way to fail between launch_owner and owners::insert.
            let conn = db.get().unwrap();
            conn.execute_batch(
                "CREATE TRIGGER poison_insert BEFORE INSERT ON paired_owners
                 WHEN NEW.label = 'poison'
                 BEGIN SELECT RAISE(ABORT, 'poisoned insert'); END;",
            )
            .unwrap();
        }

        let err = sup.pair_owner([7u8; 32], Some("poison".into())).await;
        assert!(err.is_err());
        assert_eq!(arti.launched().len(), 1, "launch did happen");
        assert_eq!(arti.live_onions(), 0, "onion dropped on teardown");
        assert_eq!(sup.liveness().await, (0, 0), "no zombie task");
        {
            let conn = db.get().unwrap();
            assert!(owners::get(&conn, &[7u8; 32]).unwrap().is_none());
        }

        // The port freed by the teardown is reused by the next pair.
        let (_, _) = sup.pair_owner([8u8; 32], None).await.unwrap();
        assert_eq!(arti.launched().last().unwrap().1, 28930);
    }

    /// restore_all relaunches every persisted Owner but skips (and does
    /// not brick on) a corrupt row (L2).
    #[tokio::test]
    async fn restore_all_skips_corrupt_row() {
        let arti = StubArti::new();
        let (sup, db, _media) = supervisor(arti.clone(), (28940, 28949));
        {
            let conn = db.get().unwrap();
            owners::insert(
                &conn,
                &PairedOwner {
                    pubkey: vec![1u8; 32],
                    label: None,
                    paired_at: 1,
                    relay_onion_address: "a.onion".into(),
                    local_port: 28941,
                    storage_cap_bytes: None,
                },
            )
            .unwrap();
            // Corrupt: pubkey is not 32 bytes.
            owners::insert(
                &conn,
                &PairedOwner {
                    pubkey: vec![9u8; 5],
                    label: None,
                    paired_at: 2,
                    relay_onion_address: "b.onion".into(),
                    local_port: 28942,
                    storage_cap_bytes: None,
                },
            )
            .unwrap();
        }

        sup.restore_all().await.unwrap();
        assert_eq!(sup.liveness().await.1, 1, "good row restored, bad skipped");
        assert_eq!(arti.launched(), vec![(hex::encode([1u8; 32]), 28941)]);
    }

    /// A wire `POST /unpair` (the router's UnpairHandle sending on the
    /// channel) is serviced by the dispatcher: after the response-flush
    /// grace the owner is fully unpaired — task gone, onion dropped, row
    /// wiped.
    #[tokio::test]
    async fn wire_unpair_dispatcher_unpairs_owner() {
        let arti = StubArti::new();
        let (sup, db, _media) = supervisor(arti.clone(), (28960, 28969));
        let sup = Arc::new(sup);
        sup.spawn_unpair_dispatcher();
        let pk = [6u8; 32];
        sup.pair_owner(pk, None).await.unwrap();
        assert_eq!(sup.liveness().await.1, 1);

        // Exactly what the per-owner router's hook does on a signed POST.
        sup.unpair_tx.send(pk).unwrap();

        // UNPAIR_RESPONSE_GRACE + the wipe itself; poll up to ~5s.
        for _ in 0..100 {
            if sup.liveness().await.1 == 0 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert_eq!(sup.liveness().await, (0, 0), "task gone");
        assert_eq!(arti.live_onions(), 0, "onion unpublished");
        let conn = db.get().unwrap();
        assert!(owners::get(&conn, &pk).unwrap().is_none(), "row wiped");
    }

    /// unpair wipes the DB row, removes the media namespace dir, and drops
    /// the onion.
    #[tokio::test]
    async fn unpair_wipes_row_media_dir_and_onion() {
        let arti = StubArti::new();
        let (sup, db, media) = supervisor(arti.clone(), (28950, 28959));
        let pk = [4u8; 32];
        sup.pair_owner(pk, None).await.unwrap();

        let owner_dir = media.path().join(hex::encode(pk));
        std::fs::create_dir_all(owner_dir.join("aa/aaaa")).unwrap();
        std::fs::write(owner_dir.join("aa/aaaa/blob"), b"x").unwrap();

        sup.unpair_owner(pk).await.unwrap();
        assert_eq!(arti.live_onions(), 0, "onion unpublished");
        assert!(!owner_dir.exists(), "media namespace removed");
        {
            let conn = db.get().unwrap();
            assert!(owners::get(&conn, &pk).unwrap().is_none());
        }
        assert_eq!(sup.liveness().await, (0, 0));
    }

    /// Plan 20 end-to-end at the supervisor level: a paired owner's router
    /// serves `/ws/voice`; a token join reaches the shared SFU; unpair
    /// drops the owner's slots AND ends the live call.
    #[tokio::test(flavor = "multi_thread")]
    async fn voice_ws_served_and_unpair_ends_calls(
    ) {
        use futures::{SinkExt, StreamExt};
        use starling_relay_voice::{VoiceServer, VoiceServerCfg};
        use starling_wire::voice::{ClientFrame, ServerFrame};
        use tokio_tungstenite::tungstenite::Message;

        let voice = VoiceServer::start(VoiceServerCfg {
            bind: "127.0.0.1:0".parse().unwrap(),
            advertised_addrs: Vec::new(),
            max_participants: 12,
            max_concurrent_calls: 4,
            idle_reap: std::time::Duration::from_secs(60),
        })
        .await
        .unwrap();

        let arti = StubArti::new();
        let db = Db::open_in_memory().unwrap();
        let media = tempfile::tempdir().unwrap();
        let sup = Supervisor::new(
            db.clone(),
            arti as Arc<dyn OnionLauncher>,
            media.path().to_path_buf(),
            Caps::default(),
            "admin.onion".into(),
            (28970, 28979),
            Some((voice.clone(), 12)),
        );

        let pk = [7u8; 32];
        sup.pair_owner(pk, None).await.unwrap();
        let token = [0x99u8; 32];
        voice
            .register_slots(
                pk,
                vec![starling_wire::voice::VoiceSlotEntry {
                    token_hash: starling_wire::blake2b256(&token).to_vec(),
                    max_participants: None,
                }],
            )
            .await;

        // The owner's loopback router serves the merged /ws/voice route.
        let (mut ws, resp) =
            tokio_tungstenite::connect_async("ws://127.0.0.1:28970/ws/voice").await.unwrap();
        assert_eq!(resp.status().as_u16(), 101);
        ws.send(Message::Binary(ClientFrame::Join { token: token.to_vec() }.to_cbor()))
            .await
            .unwrap();
        let ack = ws.next().await.unwrap().unwrap();
        let Message::Binary(bytes) = ack else { panic!("expected binary JoinAck") };
        assert!(matches!(
            ServerFrame::parse(&bytes).unwrap(),
            ServerFrame::JoinAck { .. }
        ));
        assert_eq!(voice.overview().await.get(&pk), Some(&1), "one live call");

        // Unpair: live call ends (Bye + close) and the token is dead.
        sup.unpair_owner(pk).await.unwrap();
        let mut got_bye = false;
        while let Some(Ok(msg)) = ws.next().await {
            if let Message::Binary(bytes) = msg {
                if matches!(ServerFrame::parse(&bytes), Some(ServerFrame::Bye {})) {
                    got_bye = true;
                }
            }
        }
        assert!(got_bye, "unpair sends bye to live participants");
        assert!(voice.overview().await.is_empty(), "no live calls remain");
    }
}
