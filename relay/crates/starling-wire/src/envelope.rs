//! The `/events` transport Envelope (`models/envelope.dart`).
//!
//! CBOR `{version, items:[{type, payload, extensions}], extensions}`. The
//! relay only ever produces envelopes of `type:"event"` items whose
//! `payload` is a stored `EncryptedEvent` blob, served back verbatim — it
//! never re-encrypts. Field order matches the Dart `toMap()` so the bytes
//! line up with phone-captured fixtures.

use std::collections::BTreeMap;

use serde::Serialize;
use serde_bytes::ByteBuf;

type Extensions = BTreeMap<String, ByteBuf>;

#[derive(Serialize)]
struct EnvelopeItemWire<'a> {
    #[serde(rename = "type")]
    typ: &'static str,
    #[serde(with = "serde_bytes")]
    payload: &'a [u8],
    extensions: Extensions,
}

#[derive(Serialize)]
struct EnvelopeWire<'a> {
    version: &'a str,
    items: Vec<EnvelopeItemWire<'a>>,
    extensions: Extensions,
}

/// Build a CBOR Envelope wrapping each stored event payload as an
/// `{type:"event"}` item. `version` should be [`crate::PROTOCOL_VERSION`].
pub fn build_events_envelope<'a, I>(version: &str, payloads: I) -> Vec<u8>
where
    I: IntoIterator<Item = &'a [u8]>,
{
    let items = payloads
        .into_iter()
        .map(|payload| EnvelopeItemWire {
            typ: "event",
            payload,
            extensions: Extensions::new(),
        })
        .collect();
    let envelope = EnvelopeWire {
        version,
        items,
        extensions: Extensions::new(),
    };
    let mut buf = Vec::new();
    ciborium::into_writer(&envelope, &mut buf).expect("serialize Envelope");
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use ciborium::value::Value;

    #[test]
    fn envelope_shape_matches_dart() {
        let p1 = vec![1u8, 2, 3];
        let p2 = vec![9u8, 9];
        let payloads: Vec<&[u8]> = vec![&p1, &p2];
        let bytes = build_events_envelope("2026-04-28", payloads);

        let value: Value = ciborium::from_reader(&bytes[..]).unwrap();
        let map = value.as_map().expect("top-level map");
        // version
        let version = map
            .iter()
            .find(|(k, _)| k.as_text() == Some("version"))
            .and_then(|(_, v)| v.as_text())
            .unwrap();
        assert_eq!(version, "2026-04-28");
        // items: 2 entries, each {type:"event", payload: bytes, extensions:{}}
        let items = map
            .iter()
            .find(|(k, _)| k.as_text() == Some("items"))
            .and_then(|(_, v)| v.as_array())
            .unwrap();
        assert_eq!(items.len(), 2);
        let first = items[0].as_map().unwrap();
        let typ = first
            .iter()
            .find(|(k, _)| k.as_text() == Some("type"))
            .and_then(|(_, v)| v.as_text())
            .unwrap();
        assert_eq!(typ, "event");
        let payload = first
            .iter()
            .find(|(k, _)| k.as_text() == Some("payload"))
            .and_then(|(_, v)| v.as_bytes())
            .unwrap();
        assert_eq!(payload, &[1u8, 2, 3]);
    }
}
