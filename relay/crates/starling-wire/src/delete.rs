//! `POST /events/delete` + `POST /media/delete` bodies and receipt
//! (`services/relay_push_service.dart`).
//!
//! Owner-signed batch deletes. All deletion *decisions* live on the phone
//! (tombstones, prune horizon) — the relay never learns why an id dies,
//! only that its Owner asked. Both routes are idempotent: re-deleting an
//! absent id is counted in `missing`, never an error, so a crashed or
//! replayed pass converges instead of failing.

use serde::{Deserialize, Serialize};

/// The `POST /events/delete` request body: plaintext event ids to remove.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DeleteEventsRequest {
    pub ids: Vec<String>,
}

impl DeleteEventsRequest {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize DeleteEventsRequest");
        buf
    }
}

/// The `POST /media/delete` request body: media hashes (64-char lowercase
/// hex) to remove.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DeleteMediaRequest {
    pub hashes: Vec<String>,
}

impl DeleteMediaRequest {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize DeleteMediaRequest");
        buf
    }
}

/// The `200` receipt both delete routes return. `deleted + missing` always
/// equals the request's item count.
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub struct DeleteReceipt {
    pub deleted: i64,
    pub missing: i64,
}

impl DeleteReceipt {
    pub fn parse(body: &[u8]) -> Option<Self> {
        ciborium::from_reader(body).ok()
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        ciborium::into_writer(self, &mut buf).expect("serialize DeleteReceipt");
        buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delete_requests_roundtrip() {
        let ev = DeleteEventsRequest {
            ids: vec!["evt1".into(), "evt2".into()],
        };
        let back = DeleteEventsRequest::parse(&ev.to_cbor()).unwrap();
        assert_eq!(back.ids, vec!["evt1", "evt2"]);

        let md = DeleteMediaRequest {
            hashes: vec!["aa".repeat(32)],
        };
        let back = DeleteMediaRequest::parse(&md.to_cbor()).unwrap();
        assert_eq!(back.hashes, vec!["aa".repeat(32)]);
    }

    #[test]
    fn delete_receipt_roundtrips() {
        let r = DeleteReceipt {
            deleted: 3,
            missing: 1,
        };
        let back = DeleteReceipt::parse(&r.to_cbor()).unwrap();
        assert_eq!(back.deleted, 3);
        assert_eq!(back.missing, 1);
    }
}
