//! `POST /events` push body + receipt (`services/relay_push_service.dart`).
//!
//! Body: `{items:[{id, payload}]}` where `payload` is a raw `EncryptedEvent`
//! CBOR blob. Receipt: `{accepted, rejected}`.

use serde::{Deserialize, Serialize};

/// One pushed event: the plaintext `id` plus the opaque encrypted blob.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PushItem {
    pub id: String,
    #[serde(with = "serde_bytes")]
    pub payload: Vec<u8>,
}

/// The `POST /events` request body.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PushBatch {
    pub items: Vec<PushItem>,
}

impl PushBatch {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }
}

/// The `202` receipt the relay returns.
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub struct PushReceipt {
    pub accepted: i64,
    pub rejected: i64,
}

impl PushReceipt {
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize PushReceipt");
        buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_batch_roundtrips() {
        let batch = PushBatch {
            items: vec![
                PushItem {
                    id: "evt1".into(),
                    payload: vec![1, 2, 3],
                },
                PushItem {
                    id: "evt2".into(),
                    payload: vec![4, 5],
                },
            ],
        };
        let mut buf = Vec::new();
        ciborium::into_writer(&batch, &mut buf).unwrap();
        let back = PushBatch::parse(&buf).unwrap();
        assert_eq!(back.items.len(), 2);
        assert_eq!(back.items[0].id, "evt1");
        assert_eq!(back.items[1].payload, vec![4, 5]);
    }
}
