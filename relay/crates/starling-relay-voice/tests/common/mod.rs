//! Loopback test harness: a full-ICE str0m client (RTP mode) over a real
//! UDP socket, driving its signaling through `VoiceHandle::open_session`
//! exactly like the WS adapter does in production.
#![allow(dead_code)] // shared across test binaries; not all use every helper

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Once;
use std::time::{Duration, Instant};

use starling_relay_voice::{VoiceHandle, VoiceServer, VoiceServerCfg};
use starling_wire::voice::{ClientFrame, ServerFrame, VoiceSlotEntry};
use str0m::change::SdpPendingOffer;
use str0m::change::{SdpAnswer, SdpOffer};
use str0m::format::Codec;
use str0m::media::{Direction, MediaKind, Mid};
use str0m::net::{Protocol, Receive};
use str0m::rtp::Ssrc;
use str0m::rtp::RtpWrite;
use str0m::{Candidate, Event, Input, Output, Rtc};
use tokio::net::UdpSocket;
use tokio::sync::mpsc::error::TryRecvError;

pub fn install_crypto() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let _ = env_logger::builder().is_test(true).try_init();
        // str0m logs via `tracing`, the rest of the crate via `log`.
        let _ = tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .try_init();
        str0m::crypto::from_feature_flags().install_process_default();
    });
}

pub async fn start_server(
    max_participants: u16,
    max_concurrent_calls: usize,
    idle_reap: Duration,
) -> VoiceHandle {
    install_crypto();
    VoiceServer::start(VoiceServerCfg {
        bind: "127.0.0.1:0".parse().unwrap(),
        advertised_addrs: Vec::new(),
        max_participants,
        max_concurrent_calls,
        idle_reap,
    })
    .await
    .expect("start voice server")
}

pub fn slot(token: &[u8; 32], max_participants: Option<u16>) -> VoiceSlotEntry {
    VoiceSlotEntry {
        token_hash: starling_wire::blake2b256(token).to_vec(),
        max_participants,
    }
}

pub struct TestClient {
    pub rtc: Rtc,
    socket: UdpSocket,
    addr: SocketAddr,
    tx: Option<starling_relay_voice::SessionTx>,
    rx: tokio::sync::mpsc::Receiver<ServerFrame>,
    pub sfu_id: String,
    pub cap: u32,
    pub join_participants: Vec<String>,
    mic_mid: Option<Mid>,
    mic_ssrc: Ssrc,
    mic_declared: bool,
    pending: Option<SdpPendingOffer>,
    next_timeout: Option<Instant>,
    /// sender's mid (on this client) → payloads received on it.
    pub received: HashMap<String, Vec<Vec<u8>>>,
    pub ssrc_to_mid: HashMap<u32, String>,
    /// sfu_id → mid, from PeerJoined.
    pub peer_mids: HashMap<String, String>,
    pub peers_left: Vec<String>,
    pub got_full: bool,
    pub got_bye: bool,
    pub last_error: Option<(String, String)>,
    /// The server closed our session channel.
    pub session_closed: bool,
    seq: u64,
    /// Diagnostics: count of RTP-sized datagrams actually transmitted.
    pub rtp_tx_count: usize,
}

impl TestClient {
    /// Open a session and send `join{token}`. The join outcome arrives via
    /// frames — pump and inspect.
    pub async fn join(handle: &VoiceHandle, owner: [u8; 32], token: &[u8; 32]) -> Self {
        install_crypto();
        let channels = handle.open_session(owner).await.expect("open_session");
        let socket = UdpSocket::bind("127.0.0.1:0").await.expect("bind client socket");
        let addr = socket.local_addr().unwrap();
        let mut rtc = Rtc::builder().set_rtp_mode(true).build(Instant::now());
        rtc.add_local_candidate(Candidate::host(addr, "udp").unwrap());
        let client = TestClient {
            rtc,
            socket,
            addr,
            tx: Some(channels.tx),
            rx: channels.rx,
            sfu_id: String::new(),
            cap: 0,
            join_participants: Vec::new(),
            mic_mid: None,
            mic_ssrc: 0xC0FFEE.into(),
            mic_declared: false,
            pending: None,
            next_timeout: None,
            received: HashMap::new(),
            ssrc_to_mid: HashMap::new(),
            peer_mids: HashMap::new(),
            peers_left: Vec::new(),
            got_full: false,
            got_bye: false,
            last_error: None,
            session_closed: false,
            seq: 0,
            rtp_tx_count: 0,
        };
        if let Some(tx) = &client.tx {
            tx.frame(ClientFrame::Join { token: token.to_vec() }).await;
        }
        client
    }

    pub fn is_connected(&self) -> bool {
        self.rtc.is_connected()
    }

    /// Leave by dropping the session (what a dead WS looks like).
    pub async fn leave(&mut self) {
        if let Some(tx) = self.tx.take() {
            tx.close().await;
        }
    }

    /// Payloads received on the m-line that `PeerJoined` mapped to `sfu_id`.
    pub fn received_from(&self, sfu_id: &str) -> Vec<Vec<u8>> {
        let Some(mid) = self.peer_mids.get(sfu_id) else { return Vec::new() };
        self.received.get(mid).cloned().unwrap_or_default()
    }

    /// Write one RTP payload on the mic m-line (once negotiated).
    pub fn send_audio(&mut self, payload: &[u8]) {
        assert!(self.mic_declared, "mic not negotiated yet");
        let pt = self
            .rtc
            .codec_config()
            .find(|p| p.spec().codec == Codec::Opus)
            .map(|p| p.pt())
            .expect("negotiated opus");
        self.seq += 1;
        let now = Instant::now();
        let mut direct = self.rtc.direct_api();
        let stream = direct.stream_tx(&self.mic_ssrc).expect("declared mic stream");
        stream.write_rtp(RtpWrite::new(
            pt,
            self.seq.into(),
            (self.seq as u32) * 960,
            now,
            payload.to_vec(),
        ));
        drop(direct);
        // str0m releases written RTP to the send path when time advances.
        let _ = self.rtc.handle_input(Input::Timeout(now));
    }

    /// One scheduling quantum: signaling frames, rtc timers/outputs, socket.
    pub async fn step(&mut self) {
        loop {
            match self.rx.try_recv() {
                Ok(frame) => self.on_frame(frame).await,
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    self.session_closed = true;
                    break;
                }
            }
        }

        let now = Instant::now();
        if self.next_timeout.is_some_and(|t| t <= now) {
            self.next_timeout = None;
            let _ = self.rtc.handle_input(Input::Timeout(now));
        }
        self.drain(now).await;

        let mut buf = [0u8; 2000];
        while let Ok((n, from)) = self.socket.try_recv_from(&mut buf) {
            let Ok(contents) = buf[..n].try_into() else {
                log::trace!("client {}: {n}b from {from} unparseable", self.sfu_id);
                continue;
            };
            let input = Input::Receive(
                now,
                Receive { proto: Protocol::Udp, source: from, destination: self.addr, contents },
            );
            if self.rtc.accepts(&input) {
                if let Err(e) = self.rtc.handle_input(input) {
                    log::trace!("client {}: input error {e}", self.sfu_id);
                }
                self.drain(now).await;
            } else {
                log::trace!("client {}: {n}b from {from} not accepted", self.sfu_id);
            }
        }

        tokio::time::sleep(Duration::from_millis(2)).await;
    }

    async fn drain(&mut self, now: Instant) {
        loop {
            match self.rtc.poll_output() {
                Ok(Output::Timeout(t)) => {
                    self.next_timeout = Some(t);
                    break;
                }
                Ok(Output::Transmit(t)) => {
                    // RTP (not RTCP): version 2 and a dynamic payload type.
                    if t.contents.len() > 12
                        && t.contents[0] >> 6 == 2
                        && (t.contents[1] & 0x7f) >= 96
                    {
                        self.rtp_tx_count += 1;
                    }
                    let _ = self.socket.try_send_to(&t.contents, t.destination);
                }
                Ok(Output::Event(ev)) => self.on_event(ev),
                Err(_) => break,
            }
        }
        let _ = now;
    }

    fn on_event(&mut self, ev: Event) {
        if let Event::RtpPacket(p) = ev {
            let ssrc: u32 = *p.header.ssrc;
            if let Some(mid) = p.header.ext_vals.mid {
                self.ssrc_to_mid.entry(ssrc).or_insert_with(|| mid.to_string());
            }
            match self.ssrc_to_mid.get(&ssrc) {
                Some(mid) => {
                    self.received.entry(mid.clone()).or_default().push(p.payload.to_vec())
                }
                None => log::trace!("client {}: rtp with unmapped ssrc={ssrc}", self.sfu_id),
            }
        }
    }

    async fn on_frame(&mut self, frame: ServerFrame) {
        match frame {
            ServerFrame::JoinAck { sfu_id, cap, participants, .. } => {
                self.sfu_id = sfu_id;
                self.cap = cap;
                self.join_participants = participants;
                // The one client offer: a sendonly mic m-line.
                let mut api = self.rtc.sdp_api();
                let mid = api.add_media(MediaKind::Audio, Direction::SendOnly, None, None, None);
                let (offer, pending) = api.apply().expect("initial offer");
                self.mic_mid = Some(mid);
                self.pending = Some(pending);
                self.send_frame(ClientFrame::Offer { sdp: offer.to_sdp_string() }).await;
            }
            ServerFrame::Answer { sdp } => {
                let answer = SdpAnswer::from_sdp_string(&sdp).expect("parse answer");
                let pending = self.pending.take().expect("pending offer");
                self.rtc.sdp_api().accept_answer(pending, answer).expect("accept answer");
                if !self.mic_declared {
                    let mid = self.mic_mid.expect("mic mid");
                    // Adopt the SDP-created StreamTx for the m-line; a
                    // second declared stream on the same mid makes str0m's
                    // by-mid lookup (and thus sending) nondeterministic.
                    let mut direct = self.rtc.direct_api();
                    if let Some(stream) = direct.stream_tx_by_mid(mid, None) {
                        self.mic_ssrc = stream.ssrc();
                    } else {
                        direct.declare_stream_tx(self.mic_ssrc, None, mid, None);
                    }
                    self.mic_declared = true;
                }
            }
            ServerFrame::Offer { sdp } => {
                let offer = SdpOffer::from_sdp_string(&sdp).expect("parse offer");
                let answer = self.rtc.sdp_api().accept_offer(offer).expect("accept re-offer");
                self.send_frame(ClientFrame::Answer { sdp: answer.to_sdp_string() }).await;
            }
            ServerFrame::Ice { candidate } => {
                if let Ok(c) = Candidate::from_sdp_string(&candidate) {
                    self.rtc.add_remote_candidate(c);
                }
            }
            ServerFrame::PeerJoined { sfu_id, mid } => {
                self.peer_mids.insert(sfu_id, mid);
            }
            ServerFrame::PeerLeft { sfu_id } => self.peers_left.push(sfu_id),
            ServerFrame::Full {} => self.got_full = true,
            ServerFrame::Bye {} => self.got_bye = true,
            ServerFrame::Error { code, message } => self.last_error = Some((code, message)),
        }
    }

    async fn send_frame(&self, frame: ClientFrame) {
        if let Some(tx) = &self.tx {
            tx.frame(frame).await;
        }
    }
}

/// Step every client `iters` times, round-robin.
pub async fn pump(clients: &mut [&mut TestClient], iters: usize) {
    for _ in 0..iters {
        for c in clients.iter_mut() {
            c.step().await;
        }
    }
}

/// Pump until every client's Rtc reports connected (panics on timeout).
pub async fn pump_until_connected(clients: &mut [&mut TestClient]) {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if clients.iter().all(|c| c.is_connected()) {
            return;
        }
        assert!(Instant::now() < deadline, "clients did not connect in time");
        pump(clients, 5).await;
    }
}
