//! Decode-only view of an `EncryptedEvent` (`models/encrypted_event.dart`).
//!
//! A pushed event payload is CBOR
//! `{pubkey, created_at, epoch, msg_seq, nonce, payload}`. The relay reads
//! the cleartext header fields to populate `served_events` and the
//! `/manifest` response — it never touches `payload` (the encrypted blob)
//! and stores the whole payload verbatim for later replay.

use serde::Deserialize;

/// The cleartext header fields of an `EncryptedEvent`. `payload` is
/// intentionally absent: serde skips unknown CBOR map entries, so the
/// encrypted blob is never deserialized here.
#[derive(Debug, Clone, Deserialize)]
pub struct EncryptedEventHeader {
    /// Author pubkey, Crockford base32 text (as the phone stores it).
    pub pubkey: String,
    pub created_at: i64,
    pub epoch: i64,
    pub msg_seq: i64,
    #[serde(with = "serde_bytes")]
    pub nonce: Vec<u8>,
}

impl EncryptedEventHeader {
    /// Parse the header from a raw pushed `EncryptedEvent` CBOR payload.
    /// Returns `None` if the bytes are not a well-formed EncryptedEvent
    /// (the caller rejects that push item).
    pub fn parse(payload: &[u8]) -> Option<Self> {
        ciborium::from_reader(payload).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Serialize;

    #[derive(Serialize)]
    struct FullEvent {
        pubkey: String,
        created_at: i64,
        epoch: i64,
        msg_seq: i64,
        #[serde(with = "serde_bytes")]
        nonce: Vec<u8>,
        #[serde(with = "serde_bytes")]
        payload: Vec<u8>,
    }

    #[test]
    fn parses_header_ignoring_payload() {
        let ev = FullEvent {
            pubkey: "abcd".to_string(),
            created_at: 1_700_000_000,
            epoch: 2,
            msg_seq: 5,
            nonce: vec![0u8; 24],
            payload: vec![42u8; 128],
        };
        let mut buf = Vec::new();
        ciborium::into_writer(&ev, &mut buf).unwrap();
        let header = EncryptedEventHeader::parse(&buf).expect("parse");
        assert_eq!(header.pubkey, "abcd");
        assert_eq!(header.created_at, 1_700_000_000);
        assert_eq!(header.msg_seq, 5);
        assert_eq!(header.nonce.len(), 24);
    }

    #[test]
    fn rejects_garbage() {
        assert!(EncryptedEventHeader::parse(b"not cbor at all").is_none());
    }
}
