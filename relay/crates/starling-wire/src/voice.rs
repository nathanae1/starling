//! Voice (SFU) wire surface: `GET /ws/voice` signaling frames and the
//! `POST /voice/rooms` slot push (Plan 20).
//!
//! The relay hosts live calls as a forwarding-only SFU. Rooms are
//! registered as **blinded token hashes** (`BLAKE2b-256(voiceToken)`);
//! participants join with the token preimage and get a relay-assigned
//! ephemeral `sfu_id`. No pubkeys travel on this path, and the audio the
//! SFU forwards is FrameCryptor ciphertext it cannot decrypt — this module
//! stays within the crate's zero-knowledge boundary.
//!
//! Frames are CBOR maps, internally tagged on `"t"` (snake_case). The Dart
//! side (Phase C/D, `lib/services/voice/sfu_call_session.dart`) mirrors the
//! encoding; shared vectors pin it in
//! `app/starling/test/vectors/index.json`.

use serde::{Deserialize, Serialize};

/// `error.code`: the presented token preimage hashed to no registered slot.
pub const ERR_BAD_TOKEN: &str = "bad_token";
/// `error.code`: the relay is at `max_concurrent_calls`.
pub const ERR_BUSY: &str = "busy";
/// `error.code`: frame violates the protocol (e.g. `offer` before `join`).
pub const ERR_PROTOCOL: &str = "protocol";
/// `error.code`: relay-side failure unrelated to the client's input.
pub const ERR_INTERNAL: &str = "internal";

/// Phone → relay signaling frames on `/ws/voice`.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum ClientFrame {
    /// First frame after upgrade: the 32-byte room voice-token preimage.
    Join {
        #[serde(with = "serde_bytes")]
        token: Vec<u8>,
    },
    /// Client's SDP offer (sendonly mic + recvonly downstreams).
    Offer { sdp: String },
    /// Client's SDP answer to a server re-offer (roster change).
    Answer { sdp: String },
    /// Trickle ICE candidate (SDP attribute string).
    Ice { candidate: String },
    /// Clean leave. Closing the socket has the same effect.
    Bye {},
}

/// Relay → phone signaling frames on `/ws/voice`.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum ServerFrame {
    /// Admission: the ephemeral id, the SFU's host candidates, the
    /// effective call cap, and the `sfu_id`s already in the call.
    JoinAck {
        sfu_id: String,
        candidates: Vec<String>,
        cap: u32,
        participants: Vec<String>,
    },
    /// Server re-offer after a roster change (adds/removes m-lines).
    Offer { sdp: String },
    /// Server's SDP answer to the client's initial offer.
    Answer { sdp: String },
    /// Trickle ICE candidate (SDP attribute string).
    Ice { candidate: String },
    /// A participant joined; `mid` is the m-line carrying their audio in
    /// the accompanying re-offer. Clients map `sfu_id` → pubkey via the
    /// Plan 16 roster gossip — the relay never holds that mapping.
    PeerJoined { sfu_id: String, mid: String },
    PeerLeft { sfu_id: String },
    /// Call is at capacity; the socket closes after this frame.
    Full {},
    /// Call ended (owner unpaired, relay shutdown). Socket closes after.
    Bye {},
    Error { code: String, message: String },
}

impl ClientFrame {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize ClientFrame");
        buf
    }
}

impl ServerFrame {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize ServerFrame");
        buf
    }
}

/// One blinded room slot in a `POST /voice/rooms` push.
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct VoiceSlotEntry {
    /// `BLAKE2b-256(voiceToken)` — the relay never sees the preimage until
    /// a participant joins.
    #[serde(with = "serde_bytes")]
    pub token_hash: Vec<u8>,
    /// Optional per-room cap; effective cap is
    /// `min(this, relay max_participants)`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_participants: Option<u16>,
}

/// The `POST /voice/rooms` body: the owner's **full** slot set
/// (replace-the-set semantics; missing slots are deleted).
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct VoiceSlotPush {
    pub slots: Vec<VoiceSlotEntry>,
}

impl VoiceSlotPush {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize VoiceSlotPush");
        buf
    }
}

/// The `200` receipt: how many slots are now registered.
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub struct VoiceSlotReceipt {
    pub slots: i64,
}

impl VoiceSlotReceipt {
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize VoiceSlotReceipt");
        buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_frames_roundtrip() {
        let frames = vec![
            ClientFrame::Join { token: vec![0x77; 32] },
            ClientFrame::Offer { sdp: "v=0...".into() },
            ClientFrame::Answer { sdp: "v=0...".into() },
            ClientFrame::Ice { candidate: "candidate:1 1 udp 2130706431 192.0.2.1 47000 typ host".into() },
            ClientFrame::Bye {},
        ];
        for f in frames {
            let back = ClientFrame::parse(&f.to_cbor()).unwrap();
            assert_eq!(back, f);
        }
    }

    #[test]
    fn server_frames_roundtrip() {
        let frames = vec![
            ServerFrame::JoinAck {
                sfu_id: "a1b2c3d4e5f60718".into(),
                candidates: vec!["candidate:1 1 udp 2130706431 192.0.2.1 47000 typ host".into()],
                cap: 12,
                participants: vec!["0011223344556677".into()],
            },
            ServerFrame::Offer { sdp: "v=0...".into() },
            ServerFrame::Answer { sdp: "v=0...".into() },
            ServerFrame::Ice { candidate: "candidate:...".into() },
            ServerFrame::PeerJoined { sfu_id: "0011223344556677".into(), mid: "1".into() },
            ServerFrame::PeerLeft { sfu_id: "0011223344556677".into() },
            ServerFrame::Full {},
            ServerFrame::Bye {},
            ServerFrame::Error { code: ERR_BAD_TOKEN.into(), message: "unknown token".into() },
        ];
        for f in frames {
            let back = ServerFrame::parse(&f.to_cbor()).unwrap();
            assert_eq!(back, f);
        }
    }

    /// The `join` token must survive as a CBOR byte string (bstr), not an
    /// array of ints — the Dart side writes `CborBytes`.
    #[test]
    fn join_token_encodes_as_cbor_bytes() {
        let f = ClientFrame::Join { token: vec![0xAB; 32] };
        let cbor = f.to_cbor();
        let value: ciborium::value::Value = ciborium::from_reader(&cbor[..]).unwrap();
        let ciborium::value::Value::Map(entries) = value else {
            panic!("join must encode as a map");
        };
        let token = entries
            .iter()
            .find(|(k, _)| matches!(k, ciborium::value::Value::Text(t) if t == "token"))
            .map(|(_, v)| v)
            .unwrap();
        assert!(
            matches!(token, ciborium::value::Value::Bytes(b) if b.len() == 32),
            "token must be a CBOR byte string, got {token:?}"
        );
    }

    #[test]
    fn unknown_frame_tag_rejected() {
        let f = ServerFrame::Bye {};
        let mut cbor = f.to_cbor();
        // Corrupt the tag value ("bye" → "byz").
        let pos = cbor.windows(3).position(|w| w == b"bye").unwrap();
        cbor[pos + 2] = b'z';
        assert!(ClientFrame::parse(&cbor).is_none());
        assert!(ServerFrame::parse(&cbor).is_none());
    }

    #[test]
    fn slot_push_roundtrips_with_and_without_cap() {
        let push = VoiceSlotPush {
            slots: vec![
                VoiceSlotEntry { token_hash: vec![1; 32], max_participants: Some(8) },
                VoiceSlotEntry { token_hash: vec![2; 32], max_participants: None },
            ],
        };
        let back = VoiceSlotPush::parse(&push.to_cbor()).unwrap();
        assert_eq!(back, push);
        // The optional field is absent from the wire when None.
        let value: ciborium::value::Value =
            ciborium::from_reader(&push.to_cbor()[..]).unwrap();
        let text = format!("{value:?}");
        assert_eq!(text.matches("max_participants").count(), 1);
    }

    #[test]
    fn slot_receipt_encodes() {
        let receipt = VoiceSlotReceipt { slots: 3 };
        let value: ciborium::value::Value =
            ciborium::from_reader(&receipt.to_cbor()[..]).unwrap();
        let ciborium::value::Value::Map(entries) = value else {
            panic!("receipt must be a map");
        };
        assert!(entries
            .iter()
            .any(|(k, v)| matches!(k, ciborium::value::Value::Text(t) if t == "slots")
                && matches!(v, ciborium::value::Value::Integer(i) if i128::from(*i) == 3)));
    }
}
