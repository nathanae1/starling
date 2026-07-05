//! Per-participant session state: one str0m `Rtc` (ICE-Lite + RTP mode),
//! the signaling state machine, and the downstream forwarding slots.
//!
//! Negotiation contract (Plan 20): the client offers exactly once (its
//! sendonly mic). Every later SDP change is a **server re-offer** — an SDP
//! answer cannot add m-lines, so downstream m-lines for other participants
//! always arrive via re-offer, serialized one-at-a-time per session
//! (`pending_offer`), with roster changes queueing in `queued_sources`.

use std::collections::HashMap;
use std::time::Instant;

use starling_wire::voice::ServerFrame;
use str0m::change::SdpPendingOffer;
use str0m::media::Mid;
use str0m::rtp::Ssrc;
use str0m::Rtc;
use tokio::sync::mpsc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SessionState {
    /// Channels open, nothing else — waiting for `join{token}`.
    AwaitingJoin,
    /// Admitted (JoinAck sent), waiting for the client's one initial offer.
    AwaitingOffer,
    /// Negotiated; server re-offers drive all further SDP changes.
    Steady,
}

/// One downstream m-line on this session, carrying `source` participant's
/// audio. Declared (stream_tx + ssrc) once the client answers the re-offer
/// that created the m-line.
pub(crate) struct TxSlot {
    pub mid: Mid,
    pub ssrc: Ssrc,
    pub declared: bool,
}

pub(crate) struct Session {
    pub owner: [u8; 32],
    /// Relay-assigned ephemeral id, minted at join.
    pub sfu_id: String,
    /// `(owner, token_hash)` of the call, set at join.
    pub call_key: Option<([u8; 32], [u8; 32])>,
    pub state: SessionState,
    /// Created at join (AwaitingJoin sessions hold no Rtc).
    pub rtc: Option<Rtc>,
    pub to_client: mpsc::Sender<ServerFrame>,
    /// Next str0m timeout, from the last `poll_output`.
    pub next_timeout: Option<Instant>,
    /// source sid → downstream slot.
    pub tx_slots: HashMap<u64, TxSlot>,
    /// Sources awaiting the next re-offer: `(source sid, source sfu_id)`.
    pub queued_sources: Vec<(u64, String)>,
    pub pending_offer: Option<SdpPendingOffer>,
    /// Session-local SSRC allocator for downstream streams.
    pub next_ssrc: u32,
    /// This session's negotiated Opus payload type (set after the initial
    /// offer/answer).
    pub opus_pt: Option<str0m::media::Pt>,
}

impl Session {
    pub fn new(owner: [u8; 32], to_client: mpsc::Sender<ServerFrame>) -> Self {
        Session {
            owner,
            sfu_id: String::new(),
            call_key: None,
            state: SessionState::AwaitingJoin,
            rtc: None,
            to_client,
            next_timeout: None,
            tx_slots: HashMap::new(),
            queued_sources: Vec::new(),
            pending_offer: None,
            // Arbitrary private base ("ST" + counter); unique within this
            // session, which is the only scope an SSRC needs.
            next_ssrc: 0x5354_0000,
            opus_pt: None,
        }
    }

    pub fn alloc_ssrc(&mut self) -> Ssrc {
        self.next_ssrc += 1;
        (self.next_ssrc as u32).into()
    }
}
