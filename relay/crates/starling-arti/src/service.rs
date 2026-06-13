//! Per-onion-service launch + lifetime handle.

use std::sync::Arc;

use anyhow::{anyhow, Result};
use safelog::DisplayRedacted;
use tor_hsrproxy::config::{
    Encapsulation, ProxyAction, ProxyConfig, ProxyConfigBuilder, ProxyPattern, ProxyRule,
    TargetAddr,
};
use tor_hsrproxy::OnionServiceReverseProxy;
use tor_hsservice::config::OnionServiceConfigBuilder;
use tor_hsservice::{HsNickname, RunningOnionService};
use tor_rtcompat::tokio::TokioRustlsRuntime;

use arti_client::TorClient;

/// A live onion service. Holds the running service (so its background task
/// stays up) and the reverse-proxy task. Dropping it aborts the proxy and
/// unpublishes the descriptor.
pub struct OnionHandle {
    address: String,
    local_port: u16,
    proxy: Arc<OnionServiceReverseProxy>,
    _service: Arc<RunningOnionService>,
    proxy_task: tokio::task::JoinHandle<()>,
}

impl OnionHandle {
    /// The `<addr>.onion` hostname this service publishes.
    pub fn address(&self) -> &str {
        &self.address
    }

    /// The `127.0.0.1` port the reverse proxy currently forwards to.
    pub fn local_port(&self) -> u16 {
        self.local_port
    }

    /// Point the reverse proxy at a new local port. The running service and
    /// its published descriptor are untouched — the `.onion` address does
    /// not change — so this is the cheap path when the local HTTP server
    /// rebinds on a different ephemeral port. Applies to new connections
    /// only; streams already proxied keep their original target.
    pub fn retarget(&mut self, local_port: u16) -> Result<()> {
        if local_port == self.local_port {
            return Ok(());
        }
        self.proxy
            .reconfigure(proxy_config(local_port)?, tor_config::Reconfigure::AllOrNothing)
            .map_err(|e| anyhow!("reconfigure onion proxy: {e}"))?;
        self.local_port = local_port;
        Ok(())
    }
}

/// Proxy rules forwarding inbound virtual port 80 to `127.0.0.1:local_port`.
fn proxy_config(local_port: u16) -> Result<ProxyConfig> {
    let mut cfg = ProxyConfigBuilder::default();
    cfg.proxy_ports().push(ProxyRule::new(
        ProxyPattern::one_port(80).map_err(|e| anyhow!("build proxy pattern: {e}"))?,
        ProxyAction::Forward(
            Encapsulation::Simple,
            TargetAddr::Inet(format!("127.0.0.1:{local_port}").parse()?),
        ),
    ));
    cfg.build().map_err(|e| anyhow!("build ProxyConfig: {e}"))
}

impl Drop for OnionHandle {
    fn drop(&mut self) {
        self.proxy_task.abort();
        // `_service` (the Arc<RunningOnionService>) drops with `self`,
        // triggering Arti to unpublish and stop accepting INTRODUCE2 cells.
    }
}

/// Launch an onion service under `nickname`, forwarding inbound virtual
/// port 80 to `127.0.0.1:local_port`.
pub(crate) fn launch(
    client: &TorClient<TokioRustlsRuntime>,
    runtime: &TokioRustlsRuntime,
    nickname: &str,
    local_port: u16,
) -> Result<OnionHandle> {
    let nickname: HsNickname = nickname
        .parse()
        .map_err(|e| anyhow!("parse onion nickname: {e}"))?;

    let svc_cfg = OnionServiceConfigBuilder::default()
        .nickname(nickname.clone())
        .build()
        .map_err(|e| anyhow!("build OnionServiceConfig: {e}"))?;

    let (service, request_stream) = client
        .launch_onion_service(svc_cfg)
        .map_err(|e| anyhow!("launch onion service: {e}"))?;

    // Reverse proxy: every inbound BEGIN cell on virtual port 80 becomes a
    // TCP connection to 127.0.0.1:<local_port>.
    let proxy = OnionServiceReverseProxy::new(proxy_config(local_port)?);

    let proxy_runtime = runtime.clone();
    let proxy_nickname = nickname.clone();
    let proxy_for_task = Arc::clone(&proxy);
    let proxy_task = tokio::spawn(async move {
        if let Err(e) = proxy_for_task
            .handle_requests(proxy_runtime, proxy_nickname, request_stream)
            .await
        {
            log::error!("onion reverse proxy failed: {e:?}");
        }
    });

    let address = service
        .onion_address()
        .ok_or_else(|| anyhow!("onion service has no published address yet"))?
        .display_unredacted()
        .to_string();

    Ok(OnionHandle {
        address,
        local_port,
        proxy,
        _service: service,
        proxy_task,
    })
}
