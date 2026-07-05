//! Per-call state: the roster and the idle-reap clock. A call is keyed by
//! `(owner_pubkey, token_hash)` in the server's call map; the relay learns
//! nothing about a call beyond membership count and timing.

use std::time::Instant;

pub(crate) struct Call {
    /// Effective participant cap: `min(slot override, relay max)`, fixed at
    /// call creation.
    pub cap: u32,
    /// Session ids (server-internal) of current participants.
    pub participants: Vec<u64>,
    /// Set when the roster empties; the call is reaped `idle_reap` later.
    pub empty_since: Option<Instant>,
}

impl Call {
    pub fn new(cap: u32, now: Instant) -> Self {
        Call { cap, participants: Vec::new(), empty_since: Some(now) }
    }

    pub fn is_live(&self) -> bool {
        !self.participants.is_empty()
    }
}
