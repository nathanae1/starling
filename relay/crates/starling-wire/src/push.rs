//! `POST /events` push body + receipt (`services/relay_push_service.dart`).
//!
//! Body: `{items:[{id, payload}]}` where `payload` is a raw `EncryptedEvent`
//! CBOR blob. Receipt: `{accepted, rejected}`.

use serde::{Deserialize, Serialize};

fn default_item_type() -> String {
    "event".to_string()
}

/// One pushed item: the plaintext `id`, the opaque encrypted blob, and the
/// Envelope item `type`. `type` is optional on the wire and defaults to
/// `"event"` — older phones omit it and every current push is an event —
/// but the relay stores and echoes whatever it receives so a future item
/// type transits the relay tier unchanged (F4, preserve-and-forward).
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PushItem {
    pub id: String,
    #[serde(with = "serde_bytes")]
    pub payload: Vec<u8>,
    #[serde(rename = "type", default = "default_item_type")]
    pub item_type: String,
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
                    item_type: "event".into(),
                },
                PushItem {
                    id: "evt2".into(),
                    payload: vec![4, 5],
                    item_type: "event".into(),
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

    /// A body omitting `type` (older phones, hand-rolled CBOR) decodes with
    /// the field defaulting to `"event"`.
    #[test]
    fn push_item_type_defaults_to_event() {
        use ciborium::value::Value;
        let map = Value::Map(vec![
            (Value::Text("id".into()), Value::Text("evtX".into())),
            (Value::Text("payload".into()), Value::Bytes(vec![9])),
        ]);
        let batch = Value::Map(vec![(
            Value::Text("items".into()),
            Value::Array(vec![map]),
        )]);
        let mut buf = Vec::new();
        ciborium::into_writer(&batch, &mut buf).unwrap();
        let back = PushBatch::parse(&buf).unwrap();
        assert_eq!(back.items[0].item_type, "event");
    }
}
