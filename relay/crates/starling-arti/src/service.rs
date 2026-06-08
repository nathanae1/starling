//! Per-onion-service launch + lifetime handle.

use std::sync::Arc;

use anyhow::{anyhow, Result};
use safelog::DisplayRedacted;
use tor_hsrproxy::config::{
    Encapsulation, ProxyAction, ProxyConfigBuilder, ProxyPattern, ProxyRule, TargetAddr,
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
    nickname: HsNickname,
    _service: Arc<RunningOnionService>,
    proxy_task: tokio::task::JoinHandle<()>,
}

impl OnionHandle {
    /// The `<addr>.onion` hostname this service publishes.
    pub fn address(&self) -> &str {
        &self.address
    }

    /// The nickname namespacing this service's on-disk keypair.
    pub fn nickname(&self) -> &HsNickname {
        &self.nickname
    }
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
    let mut proxy_cfg = ProxyConfigBuilder::default();
    proxy_cfg.proxy_ports().push(ProxyRule::new(
        ProxyPattern::one_port(80).map_err(|e| anyhow!("build proxy pattern: {e}"))?,
        ProxyAction::Forward(
            Encapsulation::Simple,
            TargetAddr::Inet(format!("127.0.0.1:{local_port}").parse()?),
        ),
    ));
    let proxy = OnionServiceReverseProxy::new(
        proxy_cfg
            .build()
            .map_err(|e| anyhow!("build ProxyConfig: {e}"))?,
    );

    let proxy_runtime = runtime.clone();
    let proxy_nickname = nickname.clone();
    let proxy_task = tokio::spawn(async move {
        if let Err(e) = proxy
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
        nickname,
        _service: service,
        proxy_task,
    })
}
