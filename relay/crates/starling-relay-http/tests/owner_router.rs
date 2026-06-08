use axum::body::Body;
use axum::http::{Request, StatusCode};
use ciborium::value::Value;
use ed25519_dalek::{Signer, SigningKey};
use http_body_util::BodyExt;
use starling_relay_http::{owner_router, shard_path, Caps, OwnerCtx};
use starling_relay_storage::{owners, Db, PairedOwner};
use starling_wire::crockford_base32_encode;
use starling_wire::push::{PushBatch, PushItem};
use tower::ServiceExt; // oneshot

use base64::Engine;

fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

struct Fixture {
    sk: SigningKey,
    pubkey: [u8; 32],
    ctx: OwnerCtx,
    _media: tempfile::TempDir,
}

fn fixture() -> Fixture {
    let sk = SigningKey::from_bytes(&[3u8; 32]);
    let pubkey = sk.verifying_key().to_bytes();
    let db = Db::open_in_memory().unwrap();
    {
        let conn = db.get().unwrap();
        owners::insert(
            &conn,
            &PairedOwner {
                pubkey: pubkey.to_vec(),
                label: Some("phone".into()),
                paired_at: 1,
                relay_onion_address: "owner.onion".into(),
                local_port: 17000,
                storage_cap_bytes: None,
            },
        )
        .unwrap();
    }
    let media = tempfile::tempdir().unwrap();
    let ctx = OwnerCtx {
        db,
        owner_pubkey: pubkey,
        media_dir: media.path().to_path_buf(),
        caps: Caps::default(),
    };
    Fixture {
        sk,
        pubkey,
        ctx,
        _media: media,
    }
}

/// Build an EncryptedEvent CBOR payload (byte-string nonce/payload) the way
/// the phone does, so `EncryptedEventHeader::parse` accepts it.
fn make_event(pubkey_text: &str, created_at: i64, msg_seq: i64) -> Vec<u8> {
    let map = Value::Map(vec![
        (Value::Text("pubkey".into()), Value::Text(pubkey_text.into())),
        (Value::Text("created_at".into()), Value::Integer(created_at.into())),
        (Value::Text("epoch".into()), Value::Integer(0.into())),
        (Value::Text("msg_seq".into()), Value::Integer(msg_seq.into())),
        (Value::Text("nonce".into()), Value::Bytes(vec![0u8; 24])),
        (Value::Text("payload".into()), Value::Bytes(vec![1u8, 2, 3])),
    ]);
    let mut buf = Vec::new();
    ciborium::into_writer(&map, &mut buf).unwrap();
    buf
}

fn cbor(value: &impl serde::Serialize) -> Vec<u8> {
    let mut buf = Vec::new();
    ciborium::into_writer(value, &mut buf).unwrap();
    buf
}

async fn send(ctx: &OwnerCtx, req: Request<Body>) -> (StatusCode, Vec<u8>) {
    let resp = owner_router(ctx.clone()).oneshot(req).await.unwrap();
    let status = resp.status();
    let body = resp.into_body().collect().await.unwrap().to_bytes().to_vec();
    (status, body)
}

#[tokio::test]
async fn status_reports_crockford_pubkey_and_version() {
    let f = fixture();
    let (status, body) = send(
        &f.ctx,
        Request::get("/status").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["pubkey"], crockford_base32_encode(&f.pubkey));
    assert_eq!(json["version"], "2026-04-28");
    assert_eq!(json["event_count"], 0);
}

#[tokio::test]
async fn push_then_read_events_and_manifest() {
    let f = fixture();
    let pubkey_text = crockford_base32_encode(&f.pubkey);
    let payload = make_event(&pubkey_text, 1234, 7);
    let batch = PushBatch {
        items: vec![PushItem {
            id: "evt1".into(),
            payload: payload.clone(),
        }],
    };
    let body = cbor(&batch);
    let sig = f.sk.sign(&starling_wire::blake2b256(&body));

    let req = Request::post("/events")
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .header("content-type", "application/cbor")
        .body(Body::from(body))
        .unwrap();
    let (status, recv) = send(&f.ctx, req).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let receipt: ciborium::value::Value = ciborium::from_reader(&recv[..]).unwrap();
    // accepted == 1
    let accepted = receipt
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("accepted"))
        .and_then(|(_, v)| v.as_integer())
        .unwrap();
    assert_eq!(i128::from(accepted), 1);

    // GET /events → Envelope wrapping the stored payload verbatim.
    let (status, ev_body) = send(
        &f.ctx,
        Request::get("/events").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let env: ciborium::value::Value = ciborium::from_reader(&ev_body[..]).unwrap();
    let items = env
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("items"))
        .and_then(|(_, v)| v.as_array())
        .unwrap();
    assert_eq!(items.len(), 1);
    let stored = items[0]
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("payload"))
        .and_then(|(_, v)| v.as_bytes())
        .unwrap();
    assert_eq!(stored, &payload);

    // GET /manifest → one entry with the plaintext id + created_at.
    let (status, man_body) = send(
        &f.ctx,
        Request::get("/manifest").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let man: ciborium::value::Value = ciborium::from_reader(&man_body[..]).unwrap();
    let events = man
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("events"))
        .and_then(|(_, v)| v.as_array())
        .unwrap();
    assert_eq!(events.len(), 1);
}

#[tokio::test]
async fn push_auth_matrix() {
    let f = fixture();
    let batch = PushBatch { items: vec![] };
    let body = cbor(&batch);
    let good_sig = f.sk.sign(&starling_wire::blake2b256(&body));

    // Missing signature → 401.
    let (status, _) = send(
        &f.ctx,
        Request::post("/events")
            .body(Body::from(body.clone()))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // Bad signature (over different bytes) → 401.
    let bad_sig = f.sk.sign(&starling_wire::blake2b256(b"other"));
    let (status, _) = send(
        &f.ctx,
        Request::post("/events")
            .header("x-starling-pubkey", b64(&f.pubkey))
            .header("x-starling-sig", b64(&bad_sig.to_bytes()))
            .body(Body::from(body.clone()))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // Valid signature but a DIFFERENT owner → 403.
    let other_sk = SigningKey::from_bytes(&[9u8; 32]);
    let other_pk = other_sk.verifying_key().to_bytes();
    let other_sig = other_sk.sign(&starling_wire::blake2b256(&body));
    let (status, _) = send(
        &f.ctx,
        Request::post("/events")
            .header("x-starling-pubkey", b64(&other_pk))
            .header("x-starling-sig", b64(&other_sig.to_bytes()))
            .body(Body::from(body.clone()))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Valid signature, correct owner → 202.
    let (status, _) = send(
        &f.ctx,
        Request::post("/events")
            .header("x-starling-pubkey", b64(&f.pubkey))
            .header("x-starling-sig", b64(&good_sig.to_bytes()))
            .body(Body::from(body))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn media_push_get_and_validation() {
    let f = fixture();
    let hash = "a".repeat(64);
    let blob = vec![7u8; 512];
    let sig = f.sk.sign(&starling_wire::blake2b256(&blob));

    // Push.
    let (status, _) = send(
        &f.ctx,
        Request::post(format!("/media/{hash}"))
            .header("x-starling-pubkey", b64(&f.pubkey))
            .header("x-starling-sig", b64(&sig.to_bytes()))
            .header("content-type", "application/octet-stream")
            .body(Body::from(blob.clone()))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    // File landed at the sharded path.
    assert!(f.ctx.media_dir.join(shard_path(&hash)).exists());

    // Get.
    let (status, got) = send(
        &f.ctx,
        Request::get(format!("/media/{hash}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got, blob);

    // Invalid hash → 400.
    let (status, _) = send(
        &f.ctx,
        Request::get("/media/not-a-valid-hash")
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Unknown (valid-shaped) hash → 404.
    let (status, _) = send(
        &f.ctx,
        Request::get(format!("/media/{}", "b".repeat(64)))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
