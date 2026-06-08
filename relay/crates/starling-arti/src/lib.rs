//! Shared Arti (Tor) core for Starling.
//!
//! One [`ArtiNode`] owns a tokio+rustls runtime handle and a
//! [`TorClient`]. It can launch N independent onion services
//! ([`ArtiNode::launch_service`]), each reverse-proxying inbound traffic to
//! a loopback port. The phone FFI bridge uses exactly one
//! ([`ArtiNode::create_onion_service`]); the headless relay launches one
//! per paired Owner plus an admin onion.
//!
//! This crate was extracted from the phone bridge's `arti/inner.rs` so the
//! two share a single Tor implementation. Mobile-specific concerns
//! (permission trust, the SOCKS listener) are parameterized rather than
//! hard-coded:
//! - `trust_permissions` disables Arti's `fs-mistrust` unix-permission
//!   check (required on the iOS/Android sandbox, wrong on a server).
//! - the in-process SOCKS5 listener lives behind the default `socks`
//!   feature (the phone needs it; the relay sets `default-features = false`).

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use arti_client::config::CfgPath;
use arti_client::{BootstrapBehavior, TorClient, TorClientConfig};
use tor_rtcompat::tokio::TokioRustlsRuntime;

mod service;
pub use service::OnionHandle;

#[cfg(feature = "socks")]
mod socks;

/// Default nickname for the phone's single onion service. Kept constant so
/// the device's `.onion` address persists across launches (Arti namespaces
/// the descriptor signing key on disk by nickname).
pub const PHONE_HS_NICKNAME: &str = "starling";

#[derive(Clone, Copy, Default)]
pub struct StatusSnapshot {
    pub bootstrap_percent: u32,
    pub circuit_count: u32,
    pub is_ready: bool,
    pub socks_port: u16,
}

/// How [`ArtiNode::start`] should treat bootstrap. `Full` runs
/// `create_bootstrapped` and returns only when the client is ready for
/// traffic. `OnDemand` returns immediately after `create_unbootstrapped`;
/// the first outbound connection lazily kicks bootstrap.
#[derive(Clone, Copy, Debug)]
pub enum InitMode {
    Full,
    OnDemand,
}

pub struct ArtiNode {
    runtime: TokioRustlsRuntime,
    client: TorClient<TokioRustlsRuntime>,
    #[allow(dead_code)]
    data_dir: PathBuf,
    /// Convenience slot for the phone's single onion service. The relay
    /// holds its [`OnionHandle`]s externally (keyed by nickname) and leaves
    /// this `None`.
    onion: Option<OnionHandle>,
    #[cfg(feature = "socks")]
    socks_port: u16,
    #[cfg(feature = "socks")]
    socks_task: Option<tokio::task::JoinHandle<()>>,
}

impl ArtiNode {
    /// Bootstrap a Tor client rooted at `data_dir`.
    ///
    /// `trust_permissions = true` disables Arti's `fs-mistrust` unix
    /// permission check — required on mobile (the OS sandbox is the real
    /// boundary and inherited file modes trip the check). On a server pass
    /// `false` so strict ownership/permission enforcement applies; the
    /// caller is then responsible for `data_dir` (and every ancestor) being
    /// `0700`-owned by the relay user.
    pub async fn start(
        data_dir: PathBuf,
        mode: InitMode,
        trust_permissions: bool,
    ) -> Result<Self> {
        std::fs::create_dir_all(&data_dir)
            .with_context(|| format!("create data dir {}", data_dir.display()))?;

        let cache_dir = data_dir.join("cache");
        let state_dir = data_dir.join("state");
        std::fs::create_dir_all(&cache_dir).ok();
        std::fs::create_dir_all(&state_dir).ok();

        let mut cfg = TorClientConfig::builder();
        cfg.storage()
            .cache_dir(CfgPath::new_literal(cache_dir.as_path()))
            .state_dir(CfgPath::new_literal(state_dir.as_path()));
        if trust_permissions {
            cfg.storage().permissions().dangerously_trust_everyone();
        }
        let cfg = cfg
            .build()
            .map_err(|e| anyhow!("build TorClientConfig: {e}"))?;

        let runtime = TokioRustlsRuntime::current()
            .context("acquire current tokio+rustls runtime")?;

        let client = match mode {
            InitMode::Full => TorClient::with_runtime(runtime.clone())
                .config(cfg)
                .create_bootstrapped()
                .await
                .context("bootstrap TorClient")?,
            InitMode::OnDemand => TorClient::with_runtime(runtime.clone())
                .config(cfg)
                .bootstrap_behavior(BootstrapBehavior::OnDemand)
                .create_unbootstrapped()
                .context("construct unbootstrapped TorClient")?,
        };

        #[cfg(feature = "socks")]
        let (socks_port, socks_task) = {
            let (port, task) = socks::spawn_listener(client.clone()).await?;
            (port, Some(task))
        };

        Ok(Self {
            runtime,
            client,
            data_dir,
            onion: None,
            #[cfg(feature = "socks")]
            socks_port,
            #[cfg(feature = "socks")]
            socks_task,
        })
    }

    /// Launch an onion service under `nickname`, reverse-proxying inbound
    /// virtual-port-80 traffic to `127.0.0.1:local_port`. Returns an
    /// [`OnionHandle`] the caller must keep alive — dropping it unpublishes
    /// the service. Callable any number of times on one node (distinct
    /// nicknames namespace independent keypairs on disk).
    pub fn launch_service(&self, nickname: &str, local_port: u16) -> Result<OnionHandle> {
        service::launch(&self.client, &self.runtime, nickname, local_port)
    }

    /// Phone convenience: launch (or reattach to) the single
    /// [`PHONE_HS_NICKNAME`] onion forwarding to `127.0.0.1:local_port`,
    /// storing the handle internally so [`shutdown`](Self::shutdown) tears
    /// it down. Returns `<addr>.onion`. Idempotent.
    pub fn create_onion_service(&mut self, local_port: u16) -> Result<String> {
        if let Some(existing) = &self.onion {
            return Ok(existing.address().to_string());
        }
        let handle = self.launch_service(PHONE_HS_NICKNAME, local_port)?;
        let address = handle.address().to_string();
        self.onion = Some(handle);
        Ok(address)
    }

    #[cfg(feature = "socks")]
    pub fn socks_port(&self) -> u16 {
        self.socks_port
    }

    /// Drive bootstrap explicitly. Idempotent. Useful with
    /// [`InitMode::OnDemand`] to ensure readiness before issuing requests.
    pub async fn bootstrap(&self) -> Result<()> {
        self.client
            .bootstrap()
            .await
            .context("explicit TorClient bootstrap")?;
        Ok(())
    }

    pub fn status(&self) -> StatusSnapshot {
        let bs = self.client.bootstrap_status();
        let percent = (bs.as_frac() * 100.0).round().clamp(0.0, 100.0) as u32;
        let is_ready = bs.ready_for_traffic();
        // arti-client doesn't expose a live circuit count via stable API;
        // approximate 3 once ready, 0 otherwise.
        let circuit_count = if is_ready { 3 } else { 0 };
        StatusSnapshot {
            bootstrap_percent: percent,
            circuit_count,
            is_ready,
            #[cfg(feature = "socks")]
            socks_port: self.socks_port,
            #[cfg(not(feature = "socks"))]
            socks_port: 0,
        }
    }

    /// Borrow the underlying client (the relay needs it to reach the
    /// keystore for unpair-time key removal).
    pub fn client(&self) -> &TorClient<TokioRustlsRuntime> {
        &self.client
    }

    pub async fn shutdown(&mut self) {
        // Dropping the handle aborts its proxy task and unpublishes the
        // descriptor.
        self.onion.take();
        #[cfg(feature = "socks")]
        if let Some(task) = self.socks_task.take() {
            task.abort();
        }
    }
}
