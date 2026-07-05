//! The SFU event loop: one task owns the UDP socket, every session's `Rtc`,
//! and all call state. Commands arrive on an mpsc channel; there are no
//! locks and no cross-task sharing, which also gives per-call join/leave
//! serialization for free.
//!
//! Sans-IO discipline (str0m): after **every** `handle_input` the affected
//! `Rtc` is drained to `Output::Timeout` before it gets more input — the
//! `dirty` queue tracks which sessions need draining, including sessions
//! that just had RTP written into them by forwarding.

use std::collections::{HashMap, VecDeque};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use starling_wire::voice::{
    ClientFrame, ServerFrame, VoiceSlotEntry, ERR_BAD_TOKEN, ERR_BUSY, ERR_INTERNAL, ERR_PROTOCOL,
};
use str0m::change::{SdpAnswer, SdpOffer};
use str0m::format::Codec;
use str0m::media::{Direction, MediaKind};
use str0m::net::{Protocol, Receive};
use str0m::rtp::RtpWrite;
use str0m::{Candidate, Event, IceConnectionState, Input, Output, Rtc};
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, oneshot};

use crate::call::Call;
use crate::registry::SlotRegistry;
use crate::session::{Session, SessionState, TxSlot};
use crate::{SessionChannels, SessionTx, VoiceServerCfg};

type CallKey = ([u8; 32], [u8; 32]);

pub(crate) enum Command {
    RegisterSlots { owner: [u8; 32], slots: Vec<VoiceSlotEntry> },
    DropOwner { owner: [u8; 32] },
    OpenSession { owner: [u8; 32], reply: oneshot::Sender<SessionChannels> },
    SessionFrame { sid: u64, frame: ClientFrame },
    SessionClosed { sid: u64 },
    Overview { reply: oneshot::Sender<HashMap<[u8; 32], usize>> },
}

pub(crate) async fn run(
    cfg: VoiceServerCfg,
    socket: Arc<UdpSocket>,
    candidate_addrs: Vec<SocketAddr>,
    mut cmd_rx: mpsc::Receiver<Command>,
    cmd_tx: mpsc::Sender<Command>,
) {
    let mut srv = Server::new(cfg, socket.clone(), candidate_addrs, cmd_tx);
    let mut buf = vec![0u8; 2048];
    loop {
        let deadline = srv.next_deadline();
        tokio::select! {
            biased;
            cmd = cmd_rx.recv() => match cmd {
                Some(cmd) => srv.handle_command(cmd),
                None => break, // every VoiceHandle dropped — shutdown
            },
            recv = socket.recv_from(&mut buf) => match recv {
                Ok((n, from)) => srv.handle_packet(&buf[..n], from),
                Err(e) => log::warn!("voice: udp recv error: {e}"),
            },
            _ = sleep_until_opt(deadline) => {}
        }
        srv.handle_time(Instant::now());
    }
    log::info!("voice: event loop stopped");
}

async fn sleep_until_opt(deadline: Option<Instant>) {
    match deadline {
        Some(d) => tokio::time::sleep_until(tokio::time::Instant::from_std(d)).await,
        None => std::future::pending().await,
    }
}

struct Server {
    cfg: VoiceServerCfg,
    socket: Arc<UdpSocket>,
    /// `destination` for `Input::Receive`: the bound addr, or the first
    /// candidate when bound to a wildcard.
    dest_addr: SocketAddr,
    candidates: Vec<Candidate>,
    candidate_strings: Vec<String>,
    cmd_tx: mpsc::Sender<Command>,
    registry: SlotRegistry,
    sessions: HashMap<u64, Session>,
    calls: HashMap<CallKey, Call>,
    /// Sessions whose Rtc has pending output to drain.
    dirty: VecDeque<u64>,
    next_sid: u64,
    /// Process-random seed for sfu_id minting (ids are ephemeral, not
    /// secrets — uniqueness is what matters).
    id_seed: u64,
    id_counter: u64,
}

impl Server {
    fn new(
        cfg: VoiceServerCfg,
        socket: Arc<UdpSocket>,
        candidate_addrs: Vec<SocketAddr>,
        cmd_tx: mpsc::Sender<Command>,
    ) -> Self {
        let local = socket.local_addr().expect("bound socket has local_addr");
        let dest_addr = if local.ip().is_unspecified() { candidate_addrs[0] } else { local };
        let candidates: Vec<Candidate> = candidate_addrs
            .iter()
            .filter_map(|a| Candidate::host(*a, "udp").ok())
            .collect();
        let candidate_strings = candidates.iter().map(|c| c.to_string()).collect();
        let id_seed = {
            use std::hash::{BuildHasher, Hasher};
            std::collections::hash_map::RandomState::new().build_hasher().finish()
        };
        Server {
            cfg,
            socket,
            dest_addr,
            candidates,
            candidate_strings,
            cmd_tx,
            registry: SlotRegistry::default(),
            sessions: HashMap::new(),
            calls: HashMap::new(),
            dirty: VecDeque::new(),
            next_sid: 1,
            id_seed,
            id_counter: 0,
        }
    }

    // ---- inputs ---------------------------------------------------------

    fn handle_command(&mut self, cmd: Command) {
        match cmd {
            Command::RegisterSlots { owner, slots } => {
                self.registry.replace_set(owner, &slots);
            }
            Command::DropOwner { owner } => self.drop_owner(owner),
            Command::OpenSession { owner, reply } => {
                let sid = self.next_sid;
                self.next_sid += 1;
                let (to_client, rx) = mpsc::channel(64);
                self.sessions.insert(sid, Session::new(owner, to_client));
                let channels =
                    SessionChannels { tx: SessionTx::new(sid, self.cmd_tx.clone()), rx };
                if reply.send(channels).is_err() {
                    self.sessions.remove(&sid); // caller gone before the reply
                }
            }
            Command::SessionFrame { sid, frame } => self.handle_frame(sid, frame),
            Command::SessionClosed { sid } => self.close_session(sid, None),
            Command::Overview { reply } => {
                let mut out: HashMap<[u8; 32], usize> = HashMap::new();
                for ((owner, _), call) in &self.calls {
                    if call.is_live() {
                        *out.entry(*owner).or_default() += 1;
                    }
                }
                let _ = reply.send(out);
            }
        }
    }

    fn handle_packet(&mut self, buf: &[u8], from: SocketAddr) {
        let now = Instant::now();
        let Ok(contents) = buf.try_into() else {
            return; // not STUN/DTLS/RTP — ignore
        };
        let input = Input::Receive(
            now,
            Receive { proto: Protocol::Udp, source: from, destination: self.dest_addr, contents },
        );
        let Some(sid) = self
            .sessions
            .iter()
            .find(|(_, s)| s.rtc.as_ref().is_some_and(|r| r.accepts(&input)))
            .map(|(sid, _)| *sid)
        else {
            log::trace!("voice: unrouted {}-byte packet from {from}", buf.len());
            return; // no session claims it (stale or unsolicited traffic)
        };
        log::trace!("voice: route {}b {from} -> sid={sid}", buf.len());
        let session = self.sessions.get_mut(&sid).expect("sid from iteration");
        let rtc = session.rtc.as_mut().expect("accepts() implies rtc");
        if let Err(e) = rtc.handle_input(input) {
            log::debug!("voice: session input error: {e}");
            self.close_session(sid, None);
            return;
        }
        self.dirty.push_back(sid);
    }

    fn handle_time(&mut self, now: Instant) {
        let due: Vec<u64> = self
            .sessions
            .iter()
            .filter(|(_, s)| {
                s.rtc.is_some() && s.next_timeout.is_some_and(|t| t <= now)
            })
            .map(|(sid, _)| *sid)
            .collect();
        for sid in due {
            let Some(s) = self.sessions.get_mut(&sid) else { continue };
            let Some(rtc) = s.rtc.as_mut() else { continue };
            s.next_timeout = None;
            if rtc.handle_input(Input::Timeout(now)).is_err() {
                self.close_session(sid, None);
                continue;
            }
            self.dirty.push_back(sid);
        }
        self.drain_ready(now);

        let dead: Vec<CallKey> = self
            .calls
            .iter()
            .filter(|(_, c)| {
                !c.is_live() && c.empty_since.is_some_and(|t| now.duration_since(t) >= self.cfg.idle_reap)
            })
            .map(|(k, _)| *k)
            .collect();
        for key in dead {
            self.calls.remove(&key);
        }
    }

    // ---- signaling frames ------------------------------------------------

    fn handle_frame(&mut self, sid: u64, frame: ClientFrame) {
        if !self.sessions.contains_key(&sid) {
            return; // already closed
        }
        match frame {
            ClientFrame::Join { token } => self.handle_join(sid, token),
            ClientFrame::Offer { sdp } => self.handle_offer(sid, sdp),
            ClientFrame::Answer { sdp } => self.handle_answer(sid, sdp),
            ClientFrame::Ice { candidate } => self.handle_ice(sid, candidate),
            ClientFrame::Bye {} => self.close_session(sid, Some(ServerFrame::Bye {})),
        }
        self.drain_ready(Instant::now());
    }

    fn handle_join(&mut self, sid: u64, token: Vec<u8>) {
        let now = Instant::now();
        {
            let s = self.sessions.get(&sid).expect("checked by handle_frame");
            if s.state != SessionState::AwaitingJoin {
                return self.fail(sid, ERR_PROTOCOL, "join out of order");
            }
        }
        if token.len() != 32 {
            return self.fail(sid, ERR_BAD_TOKEN, "token must be 32 bytes");
        }
        let owner = self.sessions[&sid].owner;
        let token_hash = starling_wire::blake2b256(&token);
        let Some(slot) = self.registry.lookup(&owner, &token_hash) else {
            return self.fail(sid, ERR_BAD_TOKEN, "unknown room token");
        };

        let key: CallKey = (owner, token_hash);
        let relay_max = self.cfg.max_participants;
        if !self.calls.contains_key(&key) {
            let live = self.calls.values().filter(|c| c.is_live()).count();
            if live >= self.cfg.max_concurrent_calls {
                return self.fail(sid, ERR_BUSY, "relay is at max concurrent calls");
            }
            let cap = slot.max_participants.unwrap_or(relay_max).min(relay_max).max(2) as u32;
            self.calls.insert(key, Call::new(cap, now));
        }
        let call = self.calls.get_mut(&key).expect("inserted above");
        if call.participants.len() >= call.cap as usize {
            let s = self.sessions.get_mut(&sid).expect("checked");
            let _ = s.to_client.try_send(ServerFrame::Full {});
            return self.close_session(sid, None);
        }

        // Admit.
        let sfu_id = self.mint_sfu_id();
        let call = self.calls.get_mut(&key).expect("inserted above");
        call.participants.push(sid);
        call.empty_since = None;
        let cap = call.cap;
        let existing: Vec<(u64, String)> = call
            .participants
            .iter()
            .filter(|p| **p != sid)
            .filter_map(|p| self.sessions.get(p).map(|s| (*p, s.sfu_id.clone())))
            .collect();

        let mut rtc = Rtc::builder().set_ice_lite(true).set_rtp_mode(true).build(now);
        for c in &self.candidates {
            rtc.add_local_candidate(c.clone());
        }
        let s = self.sessions.get_mut(&sid).expect("checked");
        s.rtc = Some(rtc);
        s.state = SessionState::AwaitingOffer;
        s.sfu_id = sfu_id.clone();
        s.call_key = Some(key);
        self.dirty.push_back(sid);

        self.send(
            sid,
            ServerFrame::JoinAck {
                sfu_id,
                candidates: self.candidate_strings.clone(),
                cap,
                participants: existing.iter().map(|(_, id)| id.clone()).collect(),
            },
        );

        // Existing participants get the newcomer's downstream m-line on
        // their next re-offer.
        let new_sfu_id = self.sessions[&sid].sfu_id.clone();
        for (esid, _) in existing {
            if let Some(es) = self.sessions.get_mut(&esid) {
                es.queued_sources.push((sid, new_sfu_id.clone()));
            }
            self.maybe_negotiate(esid);
        }
    }

    fn handle_offer(&mut self, sid: u64, sdp: String) {
        let s = self.sessions.get_mut(&sid).expect("checked by handle_frame");
        if s.state != SessionState::AwaitingOffer {
            return self.fail(sid, ERR_PROTOCOL, "unexpected offer (client offers exactly once)");
        }
        let Ok(offer) = SdpOffer::from_sdp_string(&sdp) else {
            return self.fail(sid, ERR_PROTOCOL, "unparseable SDP offer");
        };
        let rtc = s.rtc.as_mut().expect("AwaitingOffer implies rtc");
        let answer = match rtc.sdp_api().accept_offer(offer) {
            Ok(a) => a,
            Err(e) => {
                log::debug!("voice: accept_offer failed: {e}");
                return self.fail(sid, ERR_PROTOCOL, "offer rejected");
            }
        };
        s.opus_pt = rtc
            .codec_config()
            .find(|p| p.spec().codec == Codec::Opus)
            .map(|p| p.pt());
        s.state = SessionState::Steady;
        let call_key = s.call_key.expect("joined session has call key");
        self.dirty.push_back(sid);
        self.send(sid, ServerFrame::Answer { sdp: answer.to_sdp_string() });

        // Queue downstream m-lines for everyone already in the call. This
        // REPLACES the queue: nothing can have been negotiated before
        // Steady, and join may already have queued sources redundantly.
        let others: Vec<(u64, String)> = self
            .calls
            .get(&call_key)
            .map(|c| {
                c.participants
                    .iter()
                    .filter(|p| **p != sid)
                    .filter_map(|p| self.sessions.get(p).map(|s| (*p, s.sfu_id.clone())))
                    .collect()
            })
            .unwrap_or_default();
        if let Some(s) = self.sessions.get_mut(&sid) {
            s.queued_sources = others;
        }
        self.maybe_negotiate(sid);
    }

    fn handle_answer(&mut self, sid: u64, sdp: String) {
        let s = self.sessions.get_mut(&sid).expect("checked by handle_frame");
        if s.state != SessionState::Steady || s.pending_offer.is_none() {
            return self.fail(sid, ERR_PROTOCOL, "answer without pending offer");
        }
        let Ok(answer) = SdpAnswer::from_sdp_string(&sdp) else {
            return self.fail(sid, ERR_PROTOCOL, "unparseable SDP answer");
        };
        let pending = s.pending_offer.take().expect("checked above");
        let rtc = s.rtc.as_mut().expect("Steady implies rtc");
        if let Err(e) = rtc.sdp_api().accept_answer(pending, answer) {
            log::debug!("voice: accept_answer failed: {e}");
            return self.fail(sid, ERR_INTERNAL, "answer rejected");
        }
        // The re-offer's m-lines are now negotiated. Adopt each m-line's
        // SDP-created StreamTx (its SSRC is announced in the offer). Do
        // NOT declare a second stream: streams are keyed by SSRC and
        // `stream_tx_by_midrid` picks an arbitrary one per mid, so a
        // duplicate stream makes the send path silently flaky.
        for slot in s.tx_slots.values_mut().filter(|slot| !slot.declared) {
            let mut direct = rtc.direct_api();
            if let Some(stream) = direct.stream_tx_by_mid(slot.mid, None) {
                slot.ssrc = stream.ssrc();
            } else {
                log::warn!("voice: no SDP stream for {:?}; declaring {:?}", slot.mid, slot.ssrc);
                direct.declare_stream_tx(slot.ssrc, None, slot.mid, None);
            }
            slot.declared = true;
        }
        self.dirty.push_back(sid);
        self.maybe_negotiate(sid); // roster changes queued mid-negotiation
    }

    fn handle_ice(&mut self, sid: u64, candidate: String) {
        let s = self.sessions.get_mut(&sid).expect("checked by handle_frame");
        let Some(rtc) = s.rtc.as_mut() else {
            return self.fail(sid, ERR_PROTOCOL, "ice before join");
        };
        match Candidate::from_sdp_string(&candidate) {
            Ok(c) => {
                rtc.add_remote_candidate(c);
                self.dirty.push_back(sid);
            }
            Err(e) => log::debug!("voice: ignoring bad remote candidate: {e}"),
        }
    }

    /// Issue the next server re-offer for `sid` if it is negotiable and has
    /// queued sources. One in flight per session; the rest wait.
    fn maybe_negotiate(&mut self, sid: u64) {
        let Some(s) = self.sessions.get_mut(&sid) else { return };
        if s.state != SessionState::Steady
            || s.pending_offer.is_some()
            || s.queued_sources.is_empty()
        {
            return;
        }
        // Roster may have changed while queued; drop stale/duplicate sources.
        let call_participants: Vec<u64> = s
            .call_key
            .and_then(|k| self.calls.get(&k))
            .map(|c| c.participants.clone())
            .unwrap_or_default();
        let s = self.sessions.get_mut(&sid).expect("looked up above");
        let queued: Vec<(u64, String)> = s
            .queued_sources
            .drain(..)
            .filter(|(src, _)| call_participants.contains(src) && !s.tx_slots.contains_key(src))
            .collect();
        if queued.is_empty() {
            return;
        }
        let rtc = s.rtc.as_mut().expect("Steady implies rtc");
        let mut api = rtc.sdp_api();
        let added: Vec<(u64, String, str0m::media::Mid)> = queued
            .into_iter()
            .map(|(src, sfu)| {
                let mid = api.add_media(MediaKind::Audio, Direction::SendOnly, None, None, None);
                (src, sfu, mid)
            })
            .collect();
        let Some((offer, pending)) = api.apply() else {
            return; // no actual change
        };
        s.pending_offer = Some(pending);
        for (src, _, mid) in &added {
            let ssrc = s.alloc_ssrc();
            s.tx_slots.insert(*src, TxSlot { mid: *mid, ssrc, declared: false });
        }
        self.dirty.push_back(sid);
        self.send(sid, ServerFrame::Offer { sdp: offer.to_sdp_string() });
        for (_, sfu, mid) in added {
            self.send(sid, ServerFrame::PeerJoined { sfu_id: sfu, mid: mid.to_string() });
        }
    }

    // ---- media -----------------------------------------------------------

    /// Drain every dirty session until quiescent. Forwarding RTP into a
    /// target session makes it dirty in turn.
    fn drain_ready(&mut self, now: Instant) {
        while let Some(sid) = self.dirty.pop_front() {
            self.drain_session(sid, now);
        }
    }

    fn drain_session(&mut self, sid: u64, now: Instant) {
        let socket = self.socket.clone();
        let mut forwards = Vec::new();
        let mut close = false;
        {
            let Some(s) = self.sessions.get_mut(&sid) else { return };
            let Some(rtc) = s.rtc.as_mut() else { return };
            // Packets enqueued via `write_rtp` are released to the send
            // path only when time moves forward (str0m marks the send
            // queue in handle_timeout) — nudge the clock before polling.
            if rtc.handle_input(Input::Timeout(now)).is_err() {
                close = true;
            }
            loop {
                match rtc.poll_output() {
                    Ok(Output::Timeout(t)) => {
                        s.next_timeout = Some(t);
                        break;
                    }
                    Ok(Output::Transmit(t)) => {
                        // UDP send-or-drop; a full send buffer is packet loss.
                        let _ = socket.try_send_to(&t.contents, t.destination);
                    }
                    Ok(Output::Event(ev)) => match ev {
                        Event::RtpPacket(p) => {
                            log::trace!("voice: rtp in sid={sid} ssrc={:?}", p.header.ssrc);
                            forwards.push(p);
                        }
                        Event::IceConnectionStateChange(IceConnectionState::Disconnected) => {
                            close = true;
                        }
                        _ => {}
                    },
                    Err(e) => {
                        log::debug!("voice: poll_output error: {e}");
                        close = true;
                        break;
                    }
                }
            }
            if !rtc.is_alive() {
                close = true;
            }
        }
        for p in forwards {
            self.forward_rtp(sid, p, now);
        }
        if close {
            self.close_session(sid, None);
        }
    }

    /// Fan one participant's inbound RTP out to every other participant.
    /// The payload `Arc` is cloned, never copied or inspected — forwarding
    /// is byte-identical by construction (there is no transcode path).
    fn forward_rtp(&mut self, source_sid: u64, packet: str0m::rtp::RtpPacket, now: Instant) {
        let Some(source) = self.sessions.get(&source_sid) else { return };
        let Some(key) = source.call_key else { return };
        let Some(call) = self.calls.get(&key) else { return };
        let targets: Vec<u64> =
            call.participants.iter().copied().filter(|t| *t != source_sid).collect();
        for tsid in targets {
            let Some(target) = self.sessions.get_mut(&tsid) else { continue };
            let Some(slot) = target.tx_slots.get(&source_sid) else {
                log::trace!("voice: fwd {source_sid}->{tsid}: no slot");
                continue;
            };
            if !slot.declared {
                log::trace!("voice: fwd {source_sid}->{tsid}: slot undeclared");
                continue; // still negotiating this m-line
            }
            let Some(pt) = target.opus_pt else {
                log::trace!("voice: fwd {source_sid}->{tsid}: no opus pt");
                continue;
            };
            let (mid, ssrc) = (slot.mid, slot.ssrc);
            let Some(rtc) = target.rtc.as_mut() else { continue };
            let mut direct = rtc.direct_api();
            let Some(stream) = direct.stream_tx(&ssrc) else {
                log::trace!("voice: fwd {source_sid}->{tsid}: stream_tx({ssrc:?}) missing");
                continue;
            };
            let _ = mid; // ssrc is the stream key; mid pins the m-line at declare time
            log::trace!("voice: fwd {source_sid}->{tsid} ssrc={ssrc:?} mid={mid:?}");
            stream.write_rtp(
                RtpWrite::new(
                    pt,
                    packet.seq_no,
                    packet.header.timestamp,
                    now,
                    packet.payload.clone(),
                )
                .marker(packet.header.marker)
                .ext_vals(packet.header.ext_vals.clone()),
            );
            self.dirty.push_back(tsid);
        }
    }

    // ---- lifecycle -------------------------------------------------------

    fn drop_owner(&mut self, owner: [u8; 32]) {
        self.registry.drop_owner(&owner);
        let sids: Vec<u64> = self
            .sessions
            .iter()
            .filter(|(_, s)| s.owner == owner)
            .map(|(sid, _)| *sid)
            .collect();
        for sid in sids {
            self.close_session(sid, Some(ServerFrame::Bye {}));
        }
        self.calls.retain(|(o, _), _| *o != owner);
    }

    /// Remove a session: optional final frame, roster removal, PeerLeft to
    /// the others. Dropping `to_client` ends the WS adapter's read loop.
    fn close_session(&mut self, sid: u64, final_frame: Option<ServerFrame>) {
        let Some(s) = self.sessions.remove(&sid) else { return };
        if let Some(f) = final_frame {
            let _ = s.to_client.try_send(f);
        }
        let Some(key) = s.call_key else { return };
        let Some(call) = self.calls.get_mut(&key) else { return };
        call.participants.retain(|p| *p != sid);
        if call.participants.is_empty() {
            call.empty_since = Some(Instant::now());
        }
        let remaining = call.participants.clone();
        for p in remaining {
            if let Some(ps) = self.sessions.get_mut(&p) {
                ps.tx_slots.remove(&sid);
                ps.queued_sources.retain(|(q, _)| *q != sid);
                let _ = ps.to_client.try_send(ServerFrame::PeerLeft { sfu_id: s.sfu_id.clone() });
            }
        }
    }

    fn fail(&mut self, sid: u64, code: &str, message: &str) {
        self.close_session(
            sid,
            Some(ServerFrame::Error { code: code.to_string(), message: message.to_string() }),
        );
    }

    /// Send a frame to a session; a slow or gone consumer closes the
    /// session (backpressure = the WS is stalled or dead).
    fn send(&mut self, sid: u64, frame: ServerFrame) {
        let Some(s) = self.sessions.get(&sid) else { return };
        if s.to_client.try_send(frame).is_err() {
            self.close_session(sid, None);
        }
    }

    fn mint_sfu_id(&mut self) -> String {
        self.id_counter += 1;
        let mut input = [0u8; 16];
        input[..8].copy_from_slice(&self.id_seed.to_be_bytes());
        input[8..].copy_from_slice(&self.id_counter.to_be_bytes());
        let hash = starling_wire::blake2b256(&input);
        hex::encode(&hash[..8])
    }

    fn next_deadline(&self) -> Option<Instant> {
        let rtc_next = self
            .sessions
            .values()
            .filter_map(|s| s.next_timeout)
            .min();
        let reap_next = self
            .calls
            .values()
            .filter_map(|c| c.empty_since)
            .map(|t| t + self.cfg.idle_reap)
            .min();
        match (rtc_next, reap_next) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }
}
