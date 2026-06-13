//! Shared Arti (Tor) core for Starling.
//!
//! One [`ArtiNode`] owns a tokio+rustls runtime handle and a
//! [`TorClient`]. It can launch N independent onion services
//! ([`ArtiNode::launch_service`]), each reverse-proxying inbound traffic to
//! a loopback port. Callers own the returned [`OnionHandle`]s: the phone
//! FFI bridge holds its single one at the FFI edge; the headless relay
//! holds one per paired Owner plus an admin onion.
//!
//! This crate was extracted from the phone bridge's `arti/inner.rs` so the
//! two share a single Tor implementation. Mobile-specific concerns
//! (permission trust, the SOCKS listener) are parameterized rather than
//! hard-coded:
//! - `trust_permissions` disables Arti's `fs-mistrust` unix-permission
//!   check (required on the iOS/Android sandbox, wrong on a server).
//! - the in-process SOCKS5 listener lives behind the default `socks`
//!   feature (the phone needs it; the relay sets `default-features = false`).

use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use arti_client::config::CfgPath;
use arti_client::{BootstrapBehavior, TorClient, TorClientConfig};
use tor_rtcompat::tokio::TokioRustlsRuntime;

mod service;
pub use service::OnionHandle;

#[cfg(feature = "socks")]
mod socks;

#[derive(Clone, Copy, Default)]
pub struct StatusSnapshot {
    pub bootstrap_percent: u32,
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
    /// `false` so strict ownership/permission enforcement applies.
    /// `data_dir` and the dirs under it are created `0700` here; the caller
    /// is responsible for the *ancestors* not being group/other-writable
    /// and for the whole tree being owned by the relay user.
    pub async fn start(
        data_dir: PathBuf,
        mode: InitMode,
        trust_permissions: bool,
    ) -> Result<Self> {
        ensure_private_dir(&data_dir)
            .with_context(|| format!("create data dir {}", data_dir.display()))?;

        let cache_dir = data_dir.join("cache");
        let state_dir = data_dir.join("state");
        ensure_private_dir(&cache_dir).context("create cache dir")?;
        ensure_private_dir(&state_dir).context("create state dir")?;

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
        StatusSnapshot {
            bootstrap_percent: percent,
            is_ready: bs.ready_for_traffic(),
            #[cfg(feature = "socks")]
            socks_port: self.socks_port,
            #[cfg(not(feature = "socks"))]
            socks_port: 0,
        }
    }

    /// Tear down node-owned background tasks (currently just the SOCKS
    /// listener). Onion services are owned by their callers — drop the
    /// [`OnionHandle`]s first.
    pub async fn shutdown(&mut self) {
        #[cfg(feature = "socks")]
        if let Some(task) = self.socks_task.take() {
            task.abort();
        }
    }
}

/// Create `path` (and missing parents) with mode `0700`, then re-assert
/// `0700` on `path` itself. Arti's `fs-mistrust` (strict when
/// `trust_permissions = false`) rejects group/other-accessible state and
/// cache dirs, and a plain `create_dir_all` under the usual umask 022
/// yields `0755`. The trailing chmod heals dirs a pre-fix build left
/// behind — `DirBuilder::mode` does not apply to dirs that already exist.
fn ensure_private_dir(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
        std::fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(path)?;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    }
    #[cfg(not(unix))]
    std::fs::create_dir_all(path)?;
    Ok(())
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn mode_of(path: &Path) -> u32 {
        std::fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn ensure_private_dir_creates_0700() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("parent").join("child");
        ensure_private_dir(&dir).unwrap();
        assert_eq!(mode_of(&dir), 0o700);
        assert_eq!(mode_of(&dir.parent().unwrap()), 0o700);
    }

    #[test]
    fn ensure_private_dir_heals_existing_0755() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("state");
        std::fs::create_dir(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        ensure_private_dir(&dir).unwrap();
        assert_eq!(mode_of(&dir), 0o700);
    }
}
