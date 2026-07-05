//! Audio SFU forwarder for the Starling relay (Plan 20).
//!
//! One [`VoiceServer`] serves every paired Owner: a single UDP socket and a
//! single event-loop task own all per-participant str0m `Rtc` instances.
//! Each participant is one DTLS-SRTP leg; RTP payloads are forwarded
//! byte-identically to every other participant in the call. Payloads are
//! FrameCryptor ciphertext end-to-end encrypted by the clients — this crate
//! never decodes, mixes, or inspects audio, and links no audio codec
//! (enforced by the zero-knowledge dep-walk test in `starling-relay-http`).
//!
//! Rooms are registered as blinded token hashes ([`VoiceHandle::register_slots`]);
//! participants join with the token preimage over a WS signaling session
//! ([`VoiceHandle::open_session`]) and are known only by an ephemeral
//! `sfu_id`. No identities exist on this path.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use starling_wire::voice::{ClientFrame, ServerFrame, VoiceSlotEntry};
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, oneshot};

mod call;
mod ice;
mod registry;
mod server;
mod session;
mod ws;

pub use ws::voice_ws_router;

use server::Command;

/// An address the SFU advertises as an ICE host candidate in addition to
/// the auto-detected interface addresses (`[voice] advertised_addrs`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdvertisedAddr {
    /// Full socket address — for NAT port-forwards where the external port
    /// differs from the bound one.
    Full(SocketAddr),
    /// Bare IP; the actually-bound UDP port is appended at startup.
    IpOnly(IpAddr),
}

impl FromStr for AdvertisedAddr {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self> {
        if let Ok(sa) = s.parse::<SocketAddr>() {
            return Ok(AdvertisedAddr::Full(sa));
        }
        if let Ok(ip) = s.parse::<IpAddr>() {
            return Ok(AdvertisedAddr::IpOnly(ip));
        }
        anyhow::bail!("not an IP or socket address: {s:?}")
    }
}

#[derive(Debug, Clone)]
pub struct VoiceServerCfg {
    /// UDP bind address. Port 0 = OS-assigned (useless behind a
    /// port-forward; the binary warns).
    pub bind: SocketAddr,
    pub advertised_addrs: Vec<AdvertisedAddr>,
    /// Relay-wide per-call participant ceiling (`[voice] max_participants`).
    /// A slot's own `max_participants` can only lower it.
    pub max_participants: u16,
    /// Live (non-empty) calls across all owners.
    pub max_concurrent_calls: usize,
    /// How long an empty call lingers before it is reaped.
    pub idle_reap: Duration,
}

impl Default for VoiceServerCfg {
    fn default() -> Self {
        VoiceServerCfg {
            bind: "0.0.0.0:0".parse().expect("valid addr"),
            advertised_addrs: Vec::new(),
            max_participants: 12,
            max_concurrent_calls: 4,
            idle_reap: Duration::from_secs(60),
        }
    }
}

pub struct VoiceServer;

impl VoiceServer {
    /// Bind the UDP socket, resolve candidate addresses, and spawn the
    /// event-loop task. The returned handle is the only way in.
    pub async fn start(cfg: VoiceServerCfg) -> Result<VoiceHandle> {
        // Process-global DTLS/SRTP crypto provider (pure-Rust backend).
        static CRYPTO: std::sync::Once = std::sync::Once::new();
        CRYPTO.call_once(|| {
            str0m::crypto::from_feature_flags().install_process_default();
        });

        let socket = UdpSocket::bind(cfg.bind)
            .await
            .with_context(|| format!("bind voice UDP socket on {}", cfg.bind))?;
        let local_addr = socket.local_addr().context("voice socket local_addr")?;
        let candidates = ice::candidate_addrs(local_addr, &cfg.advertised_addrs);
        anyhow::ensure!(
            !candidates.is_empty(),
            "voice: no usable candidate address (no non-loopback interface and no advertised_addrs)"
        );
        log::info!(
            "voice: listening on udp/{} candidates {:?}",
            local_addr.port(),
            candidates
        );

        let (cmd_tx, cmd_rx) = mpsc::channel(256);
        tokio::spawn(server::run(
            cfg,
            Arc::new(socket),
            candidates,
            cmd_rx,
            cmd_tx.clone(),
        ));
        Ok(VoiceHandle { tx: cmd_tx, local_addr })
    }
}

/// Cheap-clone handle to the voice event loop. All methods are best-effort:
/// if the loop is gone (shutdown) they become no-ops / `None`.
#[derive(Clone)]
pub struct VoiceHandle {
    tx: mpsc::Sender<Command>,
    local_addr: SocketAddr,
}

impl VoiceHandle {
    pub fn local_addr(&self) -> SocketAddr {
        self.local_addr
    }

    /// Replace `owner`'s full slot set (Plan 15 push posture: the phone
    /// always pushes the complete set).
    pub async fn register_slots(&self, owner: [u8; 32], slots: Vec<VoiceSlotEntry>) {
        let _ = self.tx.send(Command::RegisterSlots { owner, slots }).await;
    }

    /// Unpair hook: drop the owner's slots and end their live calls.
    pub async fn drop_owner(&self, owner: [u8; 32]) {
        let _ = self.tx.send(Command::DropOwner { owner }).await;
    }

    /// Open a signaling session on behalf of `owner`'s router (the WS
    /// handler). The session must present a valid token in its first frame.
    pub async fn open_session(&self, owner: [u8; 32]) -> Option<SessionChannels> {
        let (reply, rx) = oneshot::channel();
        self.tx.send(Command::OpenSession { owner, reply }).await.ok()?;
        rx.await.ok()
    }

    /// Aggregate stats for the admin dashboard: live (non-empty) call count
    /// per owner. No per-participant attribution.
    pub async fn overview(&self) -> HashMap<[u8; 32], usize> {
        let (reply, rx) = oneshot::channel();
        if self.tx.send(Command::Overview { reply }).await.is_err() {
            return HashMap::new();
        }
        rx.await.unwrap_or_default()
    }
}

/// The two directions of one participant's signaling session.
pub struct SessionChannels {
    pub tx: SessionTx,
    /// Server → client frames. `None` means the session is over and the
    /// socket should close.
    pub rx: mpsc::Receiver<ServerFrame>,
}

/// Client → server side of a session. Dropping it (e.g. the WS task dying)
/// counts as leaving.
pub struct SessionTx {
    sid: u64,
    tx: mpsc::Sender<Command>,
    closed: bool,
}

impl SessionTx {
    pub(crate) fn new(sid: u64, tx: mpsc::Sender<Command>) -> Self {
        SessionTx { sid, tx, closed: false }
    }

    pub async fn frame(&self, frame: ClientFrame) {
        let _ = self.tx.send(Command::SessionFrame { sid: self.sid, frame }).await;
    }

    pub async fn close(mut self) {
        self.closed = true;
        let _ = self.tx.send(Command::SessionClosed { sid: self.sid }).await;
    }
}

impl Drop for SessionTx {
    fn drop(&mut self) {
        if !self.closed {
            let _ = self.tx.try_send(Command::SessionClosed { sid: self.sid });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn advertised_addr_parses_socket_addr_and_bare_ip() {
        assert_eq!(
            "203.0.113.7:47000".parse::<AdvertisedAddr>().unwrap(),
            AdvertisedAddr::Full("203.0.113.7:47000".parse().unwrap())
        );
        assert_eq!(
            "203.0.113.7".parse::<AdvertisedAddr>().unwrap(),
            AdvertisedAddr::IpOnly("203.0.113.7".parse().unwrap())
        );
        assert_eq!(
            "2001:db8::1".parse::<AdvertisedAddr>().unwrap(),
            AdvertisedAddr::IpOnly("2001:db8::1".parse().unwrap())
        );
        assert!("[2001:db8::1]:47000".parse::<AdvertisedAddr>().is_ok());
        assert!("not-an-addr".parse::<AdvertisedAddr>().is_err());
    }
}
