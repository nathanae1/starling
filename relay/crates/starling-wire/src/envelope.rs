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
    typ: &'a str,
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

/// The pagination cursor carried in the envelope's top-level `extensions`
/// under the `"next"` key: CBOR `{created_at, id}` of the last item served.
/// Present only when the page was truncated; clients echo it back as
/// `GET /events?since=<created_at>&since_id=<id>`. Older clients ignore
/// unknown extension keys, so the field is backward-compatible.
#[derive(Serialize)]
struct NextCursorWire<'a> {
    created_at: i64,
    id: &'a str,
}

/// Build a CBOR Envelope wrapping each stored event payload as an
/// `{type:"event"}` item. `version` should be [`crate::PROTOCOL_VERSION`].
pub fn build_events_envelope<'a, I>(version: &str, payloads: I) -> Vec<u8>
where
    I: IntoIterator<Item = &'a [u8]>,
{
    build_events_envelope_page(version, payloads, None)
}

/// [`build_events_envelope`] with an optional `(created_at, id)` keyset
/// cursor for the next page, encoded into `extensions["next"]`. Every item
/// is `type:"event"`.
pub fn build_events_envelope_page<'a, I>(
    version: &str,
    payloads: I,
    next: Option<(i64, &str)>,
) -> Vec<u8>
where
    I: IntoIterator<Item = &'a [u8]>,
{
    build_typed_envelope_page(version, payloads.into_iter().map(|p| ("event", p)), next)
}

/// Build a paged Envelope from `(type, payload)` items, preserving each
/// item's own type so a payload the relay stored under an unknown type
/// round-trips unchanged (F4). `next`, when present, is the keyset cursor
/// for the following page in `extensions["next"]`.
pub fn build_typed_envelope_page<'a, I>(
    version: &str,
    typed_items: I,
    next: Option<(i64, &str)>,
) -> Vec<u8>
where
    I: IntoIterator<Item = (&'a str, &'a [u8])>,
{
    let items = typed_items
        .into_iter()
        .map(|(typ, payload)| EnvelopeItemWire {
            typ,
            payload,
            extensions: Extensions::new(),
        })
        .collect();
    let mut extensions = Extensions::new();
    if let Some((created_at, id)) = next {
        let mut buf = Vec::new();
        ciborium::into_writer(&NextCursorWire { created_at, id }, &mut buf)
            .expect("serialize next cursor");
        extensions.insert("next".to_string(), ByteBuf::from(buf));
    }
    let envelope = EnvelopeWire {
        version,
        items,
        extensions,
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

    #[test]
    fn next_cursor_lands_in_extensions() {
        let p1 = vec![1u8];
        let payloads: Vec<&[u8]> = vec![&p1];
        let bytes = build_events_envelope_page("2026-04-28", payloads, Some((1700, "evtA")));

        let value: Value = ciborium::from_reader(&bytes[..]).unwrap();
        let map = value.as_map().expect("top-level map");
        let extensions = map
            .iter()
            .find(|(k, _)| k.as_text() == Some("extensions"))
            .and_then(|(_, v)| v.as_map())
            .unwrap();
        let next_bytes = extensions
            .iter()
            .find(|(k, _)| k.as_text() == Some("next"))
            .and_then(|(_, v)| v.as_bytes())
            .unwrap();
        let next: Value = ciborium::from_reader(next_bytes.as_slice()).unwrap();
        let next = next.as_map().unwrap();
        let created_at = next
            .iter()
            .find(|(k, _)| k.as_text() == Some("created_at"))
            .and_then(|(_, v)| v.as_integer())
            .unwrap();
        assert_eq!(created_at, 1700.into());
        let id = next
            .iter()
            .find(|(k, _)| k.as_text() == Some("id"))
            .and_then(|(_, v)| v.as_text())
            .unwrap();
        assert_eq!(id, "evtA");
    }

    #[test]
    fn no_cursor_keeps_legacy_bytes() {
        let p1 = vec![1u8, 2, 3];
        let payloads: Vec<&[u8]> = vec![&p1];
        let legacy = build_events_envelope("2026-04-28", payloads.clone());
        let paged = build_events_envelope_page("2026-04-28", payloads, None);
        assert_eq!(legacy, paged);
    }
}
