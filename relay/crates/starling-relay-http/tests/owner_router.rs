use axum::body::Body;
use axum::http::{Request, StatusCode};
use ciborium::value::Value;
use ed25519_dalek::{Signer, SigningKey};
use http_body_util::BodyExt;
use starling_relay_http::{owner_router, owner_shard_path, Caps, OwnerCtx};
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
    fixture_with(Caps::default(), None)
}

fn fixture_with(caps: Caps, storage_cap_bytes: Option<i64>) -> Fixture {
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
                storage_cap_bytes,
            },
        )
        .unwrap();
    }
    let media = tempfile::tempdir().unwrap();
    let ctx = OwnerCtx {
        db,
        owner_pubkey: pubkey,
        media_dir: media.path().to_path_buf(),
        caps,
        unpair: None,
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
    make_event_sized(pubkey_text, created_at, msg_seq, 3)
}

/// Same, with an inner ciphertext field of `payload_len` bytes (for cap
/// tests that need bulk).
fn make_event_sized(
    pubkey_text: &str,
    created_at: i64,
    msg_seq: i64,
    payload_len: usize,
) -> Vec<u8> {
    let map = Value::Map(vec![
        (Value::Text("pubkey".into()), Value::Text(pubkey_text.into())),
        (Value::Text("created_at".into()), Value::Integer(created_at.into())),
        (Value::Text("epoch".into()), Value::Integer(0.into())),
        (Value::Text("msg_seq".into()), Value::Integer(msg_seq.into())),
        (Value::Text("nonce".into()), Value::Bytes(vec![0u8; 24])),
        (Value::Text("payload".into()), Value::Bytes(vec![1u8; payload_len])),
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
            item_type: "event".into(),
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
    // File landed at the Owner-namespaced sharded path.
    assert!(f
        .ctx
        .media_dir
        .join(owner_shard_path(&f.pubkey, &hash))
        .exists());

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

fn signed_events_push(f: &Fixture, batch: &PushBatch) -> Request<Body> {
    let body = cbor(batch);
    let sig = f.sk.sign(&starling_wire::blake2b256(&body));
    Request::post("/events")
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .header("content-type", "application/cbor")
        .body(Body::from(body))
        .unwrap()
}

fn signed_media_push(f: &Fixture, hash: &str, blob: &[u8]) -> Request<Body> {
    let sig = f.sk.sign(&starling_wire::blake2b256(blob));
    Request::post(format!("/media/{hash}"))
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .header("content-type", "application/octet-stream")
        .body(Body::from(blob.to_vec()))
        .unwrap()
}

/// D4: an event batch that would bust the Owner's combined cap → 507.
#[tokio::test]
async fn events_push_over_owner_cap_507() {
    let f = fixture_with(Caps::default(), Some(100));
    let pubkey_text = crockford_base32_encode(&f.pubkey);
    // One event whose CBOR alone exceeds the 100-byte cap.
    let batch = PushBatch {
        items: vec![PushItem {
            id: "evt-big".into(),
            payload: make_event_sized(&pubkey_text, 100, 0, 200),
            item_type: "event".into(),
        }],
    };
    let (status, body) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::INSUFFICIENT_STORAGE);
    assert_eq!(body, b"owner storage cap exceeded");
}

/// D4: the per-Owner cap covers events + media COMBINED — event bytes
/// already stored count against a later media push.
#[tokio::test]
async fn media_push_counts_event_bytes_toward_cap() {
    let f = fixture_with(Caps::default(), Some(1000));
    let pubkey_text = crockford_base32_encode(&f.pubkey);
    let batch = PushBatch {
        items: vec![PushItem {
            id: "evt1".into(),
            payload: make_event_sized(&pubkey_text, 100, 0, 800),
            item_type: "event".into(),
        }],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // Stored event bytes count toward the cap; size the blobs off the
    // actual stored total so the boundary is exact.
    let stored = {
        let conn = f.ctx.db.get().unwrap();
        starling_relay_storage::events::total_bytes(&conn, &f.pubkey).unwrap()
    };
    assert!(stored > 800 && stored < 1000, "stored={stored}");
    let bust = (1000 - stored + 1) as usize;
    let fit = (1000 - stored) as usize;

    let (status, body) =
        send(&f.ctx, signed_media_push(&f, &"d".repeat(64), &vec![1u8; bust])).await;
    assert_eq!(status, StatusCode::INSUFFICIENT_STORAGE);
    assert_eq!(body, b"owner storage cap exceeded");

    let (status, _) =
        send(&f.ctx, signed_media_push(&f, &"e".repeat(64), &vec![1u8; fit])).await;
    assert_eq!(status, StatusCode::ACCEPTED);
}

/// D4: host-wide disk cap counts ALL owners' bytes.
#[tokio::test]
async fn host_disk_cap_spans_owners_507() {
    let caps = Caps {
        per_owner_default: 0, // unlimited per owner
        disk_cap: 1000,
    };
    let db = Db::open_in_memory().unwrap();
    let media = tempfile::tempdir().unwrap();

    let mut fixtures = Vec::new();
    for seed in [3u8, 9u8] {
        let sk = SigningKey::from_bytes(&[seed; 32]);
        let pubkey = sk.verifying_key().to_bytes();
        {
            let conn = db.get().unwrap();
            owners::insert(
                &conn,
                &PairedOwner {
                    pubkey: pubkey.to_vec(),
                    label: None,
                    paired_at: 1,
                    relay_onion_address: format!("owner{seed}.onion"),
                    local_port: 17000 + seed as u16,
                    storage_cap_bytes: None,
                },
            )
            .unwrap();
        }
        fixtures.push(Fixture {
            sk,
            pubkey,
            ctx: OwnerCtx {
                db: db.clone(),
                owner_pubkey: pubkey,
                media_dir: media.path().to_path_buf(),
                caps,
                unpair: None,
            },
            _media: tempfile::tempdir().unwrap(),
        });
    }

    // Owner A fills 900 of the 1000-byte host budget.
    let (status, _) =
        send(&fixtures[0].ctx, signed_media_push(&fixtures[0], &"a".repeat(64), &[1u8; 900]))
            .await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // Owner B's 200-byte blob busts the HOST cap (B itself is unlimited).
    let (status, body) =
        send(&fixtures[1].ctx, signed_media_push(&fixtures[1], &"b".repeat(64), &[1u8; 200]))
            .await;
    assert_eq!(status, StatusCode::INSUFFICIENT_STORAGE);
    assert_eq!(body, b"relay storage cap exceeded");
}

/// D6: one router instance shares one bucket — burst 60 then 429 with
/// Retry-After. (The `send` helper builds a fresh router per request, so
/// this test drives a single instance directly.)
#[tokio::test]
async fn rate_limit_429_after_burst() {
    let f = fixture();
    let router = owner_router(f.ctx.clone());
    for i in 0..60 {
        let resp = router
            .clone()
            .oneshot(Request::get("/status").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK, "request {i} within burst");
    }
    let resp = router
        .clone()
        .oneshot(Request::get("/status").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::TOO_MANY_REQUESTS);
    let retry_after = resp
        .headers()
        .get(axum::http::header::RETRY_AFTER)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .expect("Retry-After header");
    assert!(retry_after >= 1);
}

/// D2b: a ~3 MiB push must NOT 413 (axum's 2 MiB default did); >4 MiB must.
#[tokio::test]
async fn body_limit_is_4mib() {
    let f = fixture();
    let pubkey_text = crockford_base32_encode(&f.pubkey);

    // 3 MiB: accepted by the body limit; the junk inner payload parses as
    // an event header or not — either way the route answers, not 413.
    let batch = PushBatch {
        items: vec![PushItem {
            id: "evt-3mib".into(),
            payload: make_event_sized(&pubkey_text, 100, 0, 3 * 1024 * 1024),
            item_type: "event".into(),
        }],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // >4 MiB: rejected by DefaultBodyLimit before the handler runs.
    let batch = PushBatch {
        items: vec![PushItem {
            id: "evt-5mib".into(),
            payload: make_event_sized(&pubkey_text, 100, 0, 5 * 1024 * 1024),
            item_type: "event".into(),
        }],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
}

/// Decode a manifest CBOR body into (ids, has_older).
fn parse_manifest(body: &[u8]) -> (Vec<String>, bool) {
    let man: Value = ciborium::from_reader(body).unwrap();
    let map = man.as_map().unwrap();
    let ids = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("events"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .iter()
        .map(|e| {
            e.as_map()
                .unwrap()
                .iter()
                .find(|(k, _)| k.as_text() == Some("id"))
                .and_then(|(_, v)| v.as_text())
                .unwrap()
                .to_string()
        })
        .collect();
    let has_older = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("has_older"))
        .and_then(|(_, v)| v.as_bool())
        .unwrap();
    (ids, has_older)
}

/// >PAGE_LIMIT events, with same-second runs straddling the page boundary:
/// walking `until`/`until_id` to `has_older == false` must yield every id
/// exactly once (the old `until = oldest - 1` contract skipped same-second
/// strays).
#[tokio::test]
async fn manifest_pages_to_completion_with_until_id() {
    let f = fixture();
    {
        let conn = f.ctx.db.get().unwrap();
        // Runs of 5 events share one created_at; the boundary at 1000 falls
        // mid-run.
        for i in 0..1005 {
            starling_relay_storage::events::insert(
                &conn,
                &starling_relay_storage::ServedEvent {
                    pubkey: f.pubkey.to_vec(),
                    id: format!("evt{i:04}"),
                    created_at: (i / 5) * 10,
                    msg_seq: i,
                    nonce: vec![0u8; 24],
                    payload: vec![0u8; 4],
                    item_type: "event".into(),
                },
            )
            .unwrap();
        }
    }

    let mut seen = std::collections::HashSet::new();
    let mut uri = "/manifest".to_string();
    let mut pages = 0;
    loop {
        let (status, body) = send(
            &f.ctx,
            Request::get(&uri).body(Body::empty()).unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        let (ids, has_older) = parse_manifest(&body);
        let last = ids.last().cloned();
        for id in ids {
            assert!(seen.insert(id.clone()), "duplicate id across pages: {id}");
        }
        pages += 1;
        if !has_older {
            break;
        }
        // created_at of the oldest entry = (idx / 5) * 10, recoverable from
        // the id; keyset-cursor on (created_at, id).
        let last = last.unwrap();
        let idx: i64 = last[3..].parse().unwrap();
        uri = format!("/manifest?until={}&until_id={last}", (idx / 5) * 10);
    }
    assert_eq!(pages, 2);
    assert_eq!(seen.len(), 1005);
}

fn media_manifest_req(f: &Fixture, after: Option<&str>) -> Request<Body> {
    // Owner-sig over the empty body (it's a GET).
    let sig = f.sk.sign(&starling_wire::blake2b256(b""));
    let uri = match after {
        Some(a) => format!("/media-manifest?after={a}"),
        None => "/media-manifest".to_string(),
    };
    Request::get(uri)
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .body(Body::empty())
        .unwrap()
}

/// D8: `/media-manifest` is Owner tooling — anonymous and wrong-owner
/// requests are refused.
#[tokio::test]
async fn media_manifest_requires_owner_sig() {
    let f = fixture();
    let (status, _) = send(
        &f.ctx,
        Request::get("/media-manifest").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let other_sk = SigningKey::from_bytes(&[9u8; 32]);
    let other_sig = other_sk.sign(&starling_wire::blake2b256(b""));
    let (status, _) = send(
        &f.ctx,
        Request::get("/media-manifest")
            .header("x-starling-pubkey", b64(&other_sk.verifying_key().to_bytes()))
            .header("x-starling-sig", b64(&other_sig.to_bytes()))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

/// D8: lists the Owner's stored hashes, `hash ASC`, keyset-paged on
/// `after`.
#[tokio::test]
async fn media_manifest_lists_and_pages() {
    let f = fixture();
    for c in ["a", "b", "c"] {
        let blob = vec![1u8; 64];
        let (status, _) = send(&f.ctx, signed_media_push(&f, &c.repeat(64), &blob)).await;
        assert_eq!(status, StatusCode::ACCEPTED);
    }

    let (status, body) = send(&f.ctx, media_manifest_req(&f, None)).await;
    assert_eq!(status, StatusCode::OK);
    let page: Value = ciborium::from_reader(&body[..]).unwrap();
    let map = page.as_map().unwrap();
    let hashes: Vec<String> = map
        .iter()
        .find(|(k, _)| k.as_text() == Some("hashes"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .iter()
        .map(|h| h.as_text().unwrap().to_string())
        .collect();
    assert_eq!(hashes, vec!["a".repeat(64), "b".repeat(64), "c".repeat(64)]);

    // Keyset paging: after the first hash → the remaining two.
    let (status, body) = send(&f.ctx, media_manifest_req(&f, Some(&"a".repeat(64)))).await;
    assert_eq!(status, StatusCode::OK);
    let page: Value = ciborium::from_reader(&body[..]).unwrap();
    let hashes: Vec<String> = page
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("hashes"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .iter()
        .map(|h| h.as_text().unwrap().to_string())
        .collect();
    assert_eq!(hashes, vec!["b".repeat(64), "c".repeat(64)]);
}

/// Two paired Owners pushing different blobs under the SAME hash must not
/// clobber each other (S1: blobs are ciphertext keyed by the plaintext
/// hash, so equal hashes with different bytes is the normal case, not an
/// attack-only one).
#[tokio::test]
async fn cross_owner_media_cannot_clobber() {
    let db = Db::open_in_memory().unwrap();
    let media = tempfile::tempdir().unwrap();

    let mut owners_ctx = Vec::new();
    for seed in [3u8, 9u8] {
        let sk = SigningKey::from_bytes(&[seed; 32]);
        let pubkey = sk.verifying_key().to_bytes();
        {
            let conn = db.get().unwrap();
            owners::insert(
                &conn,
                &PairedOwner {
                    pubkey: pubkey.to_vec(),
                    label: None,
                    paired_at: 1,
                    relay_onion_address: format!("owner{seed}.onion"),
                    local_port: 17000 + seed as u16,
                    storage_cap_bytes: None,
                },
            )
            .unwrap();
        }
        let ctx = OwnerCtx {
            db: db.clone(),
            owner_pubkey: pubkey,
            media_dir: media.path().to_path_buf(),
            caps: Caps::default(),
            unpair: None,
        };
        owners_ctx.push((sk, ctx));
    }
    let (sk_a, ctx_a) = &owners_ctx[0];
    let (sk_b, ctx_b) = &owners_ctx[1];

    let hash = "c".repeat(64);
    let blob_a = vec![0xAAu8; 256];
    let blob_b = vec![0xBBu8; 256];

    for (sk, ctx, blob) in [(sk_a, ctx_a, &blob_a), (sk_b, ctx_b, &blob_b)] {
        let sig = sk.sign(&starling_wire::blake2b256(blob));
        let (status, _) = send(
            ctx,
            Request::post(format!("/media/{hash}"))
                .header("x-starling-pubkey", b64(&ctx.owner_pubkey))
                .header("x-starling-sig", b64(&sig.to_bytes()))
                .header("content-type", "application/octet-stream")
                .body(Body::from(blob.clone()))
                .unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::ACCEPTED);
    }

    // Each Owner reads back exactly the bytes they pushed.
    let (status, got_a) = send(
        ctx_a,
        Request::get(format!("/media/{hash}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got_a, blob_a);

    let (status, got_b) = send(
        ctx_b,
        Request::get(format!("/media/{hash}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got_b, blob_b);
}

/// Build a request-bound signed POST (the `X-Starling-Ts` scheme).
fn bound_signed_post(f: &Fixture, path: &str, body: Vec<u8>, ts: i64) -> Request<Body> {
    let digest = starling_wire::owner_request_digest("POST", path, ts, &body);
    let sig = f.sk.sign(&digest);
    Request::post(path)
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .header("x-starling-ts", ts.to_string())
        .header("content-type", "application/cbor")
        .body(Body::from(body))
        .unwrap()
}

/// The bound scheme: valid → 202; stale ts → 401; a signature minted for
/// one path replayed against another → 401.
#[tokio::test]
async fn bound_owner_sig_accepted_and_replay_rejected() {
    let f = fixture();
    let body = cbor(&PushBatch { items: vec![] });
    let now = starling_wire::now_secs();

    let (status, _) = send(&f.ctx, bound_signed_post(&f, "/events", body.clone(), now)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // Stale timestamp → 401 even with a matching signature.
    let (status, msg) = send(
        &f.ctx,
        bound_signed_post(&f, "/events", body.clone(), now - 3600),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(msg, b"stale x-starling-ts");

    // Cross-path replay: headers minted for /events, replayed against
    // /media-manifest (as a GET with those headers) → 401.
    let digest = starling_wire::owner_request_digest("POST", "/events", now, &body);
    let sig = f.sk.sign(&digest);
    let (status, _) = send(
        &f.ctx,
        Request::get("/media-manifest")
            .header("x-starling-pubkey", b64(&f.pubkey))
            .header("x-starling-sig", b64(&sig.to_bytes()))
            .header("x-starling-ts", now.to_string())
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

/// M4: a torn blob on disk (row says N bytes, file has fewer) heals on
/// re-push instead of being pinned forever by the idempotency check.
#[tokio::test]
async fn torn_media_blob_heals_on_repush() {
    let f = fixture();
    let hash = "f".repeat(64);
    let blob = vec![9u8; 512];

    let (status, _) = send(&f.ctx, signed_media_push(&f, &hash, &blob)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    // Simulate the torn write: truncate the blob behind the relay's back.
    let full = f.ctx.media_dir.join(owner_shard_path(&f.pubkey, &hash));
    std::fs::write(&full, &blob[..100]).unwrap();

    // Re-push: 202 and the full bytes are back.
    let (status, _) = send(&f.ctx, signed_media_push(&f, &hash, &blob)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(std::fs::read(&full).unwrap(), blob);

    // Plain duplicate re-push stays idempotent.
    let (status, _) = send(&f.ctx, signed_media_push(&f, &hash, &blob)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(std::fs::read(&full).unwrap(), blob);
}

/// M1: an oversized `PushItem.id` is rejected (counted in the receipt),
/// not stored as an unaccounted byte sink.
#[tokio::test]
async fn oversized_push_item_id_rejected() {
    let f = fixture();
    let pubkey_text = crockford_base32_encode(&f.pubkey);
    let batch = PushBatch {
        items: vec![
            PushItem {
                id: "x".repeat(65),
                payload: make_event(&pubkey_text, 100, 0),
                item_type: "event".into(),
            },
            PushItem {
                id: "evt-ok".into(),
                payload: make_event(&pubkey_text, 101, 1),
                item_type: "event".into(),
            },
        ],
    };
    let (status, body) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let receipt: Value = ciborium::from_reader(&body[..]).unwrap();
    let field = |name: &str| {
        receipt
            .as_map()
            .unwrap()
            .iter()
            .find(|(k, _)| k.as_text() == Some(name))
            .and_then(|(_, v)| v.as_integer())
            .map(i128::from)
            .unwrap()
    };
    assert_eq!(field("accepted"), 1);
    assert_eq!(field("rejected"), 1);
}

/// F4: an item with an unknown `type` is stored opaquely and served back in
/// the `/events` envelope with its type + payload intact (preserve-and-forward).
#[tokio::test]
async fn unknown_item_type_round_trips() {
    let f = fixture();
    let batch = PushBatch {
        items: vec![PushItem {
            id: "future1".into(),
            payload: vec![0xEE; 40], // not a valid EncryptedEvent header
            item_type: "future-thing".into(),
        }],
    };
    let (status, body) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let receipt: Value = ciborium::from_reader(&body[..]).unwrap();
    let accepted = receipt
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("accepted"))
        .and_then(|(_, v)| v.as_integer())
        .map(i128::from)
        .unwrap();
    assert_eq!(accepted, 1);

    let (status, body) = send(&f.ctx, Request::get("/events").body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::OK);
    let env: Value = ciborium::from_reader(&body[..]).unwrap();
    let items_arr = env
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("items"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .clone();
    let item = items_arr[0].as_map().unwrap();
    let typ = item
        .iter()
        .find(|(k, _)| k.as_text() == Some("type"))
        .and_then(|(_, v)| v.as_text())
        .unwrap();
    assert_eq!(typ, "future-thing");
    let payload = item
        .iter()
        .find(|(k, _)| k.as_text() == Some("payload"))
        .and_then(|(_, v)| v.as_bytes())
        .unwrap();
    assert_eq!(payload, &vec![0xEE; 40]);
}

/// H2/L7: `GET /events` pages by keyset; a truncated page carries the
/// `extensions["next"]` cursor, and walking it yields every payload
/// exactly once.
#[tokio::test]
async fn events_get_pages_with_next_cursor() {
    let f = fixture();
    {
        let conn = f.ctx.db.get().unwrap();
        for i in 0..501 {
            starling_relay_storage::events::insert(
                &conn,
                &starling_relay_storage::ServedEvent {
                    pubkey: f.pubkey.to_vec(),
                    id: format!("evt{i:04}"),
                    created_at: 100, // all same second — pure id-tiebreak paging
                    msg_seq: i,
                    nonce: vec![0u8; 24],
                    payload: vec![i as u8; 4],
                    item_type: "event".into(),
                },
            )
            .unwrap();
        }
    }

    let parse_page = |body: &[u8]| -> (usize, Option<(i64, String)>) {
        let env: Value = ciborium::from_reader(body).unwrap();
        let map = env.as_map().unwrap();
        let items = map
            .iter()
            .find(|(k, _)| k.as_text() == Some("items"))
            .and_then(|(_, v)| v.as_array())
            .unwrap()
            .len();
        let next = map
            .iter()
            .find(|(k, _)| k.as_text() == Some("extensions"))
            .and_then(|(_, v)| v.as_map())
            .and_then(|ext| {
                ext.iter()
                    .find(|(k, _)| k.as_text() == Some("next"))
                    .and_then(|(_, v)| v.as_bytes().cloned())
            })
            .map(|bytes| {
                let cursor: Value = ciborium::from_reader(bytes.as_slice()).unwrap();
                let m = cursor.as_map().unwrap();
                let at = m
                    .iter()
                    .find(|(k, _)| k.as_text() == Some("created_at"))
                    .and_then(|(_, v)| v.as_integer())
                    .map(|v| i128::from(v) as i64)
                    .unwrap();
                let id = m
                    .iter()
                    .find(|(k, _)| k.as_text() == Some("id"))
                    .and_then(|(_, v)| v.as_text())
                    .unwrap()
                    .to_string();
                (at, id)
            });
        (items, next)
    };

    let (status, body) = send(&f.ctx, Request::get("/events").body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::OK);
    let (count1, next) = parse_page(&body);
    assert_eq!(count1, 500);
    let (at, id) = next.expect("truncated page carries next cursor");
    assert_eq!((at, id.as_str()), (100, "evt0499"));

    let (status, body) = send(
        &f.ctx,
        Request::get(format!("/events?since={at}&since_id={id}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (count2, next) = parse_page(&body);
    assert_eq!(count2, 1);
    assert!(next.is_none());
}

// ---------------------------------------------------------------------------
// Deletion (Phase 3): POST /events/delete + POST /media/delete
// ---------------------------------------------------------------------------

fn signed_delete(f: &Fixture, path: &str, body: Vec<u8>) -> Request<Body> {
    let ts = starling_wire::now_secs();
    let digest = starling_wire::owner_request_digest("POST", path, ts, &body);
    let sig = f.sk.sign(&digest);
    Request::post(path)
        .header("x-starling-pubkey", b64(&f.pubkey))
        .header("x-starling-sig", b64(&sig.to_bytes()))
        .header("x-starling-ts", ts.to_string())
        .header("content-type", "application/cbor")
        .body(Body::from(body))
        .unwrap()
}

fn parse_delete_receipt(body: &[u8]) -> (i64, i64) {
    let v: Value = ciborium::from_reader(body).unwrap();
    let field = |name: &str| {
        v.as_map()
            .unwrap()
            .iter()
            .find(|(k, _)| k.as_text() == Some(name))
            .and_then(|(_, val)| val.as_integer())
            .map(|i| i128::from(i) as i64)
            .unwrap()
    };
    (field("deleted"), field("missing"))
}

/// Deleting an event removes it from BOTH read surfaces (`/manifest` and
/// the `/events` envelope); a second identical delete is idempotent and
/// counts the ids as missing.
#[tokio::test]
async fn events_delete_removes_and_is_idempotent() {
    let f = fixture();
    let pubkey_text = crockford_base32_encode(&f.pubkey);
    let batch = PushBatch {
        items: vec![
            PushItem {
                id: "evt-keep".into(),
                payload: make_event(&pubkey_text, 100, 0),
                item_type: "event".into(),
            },
            PushItem {
                id: "evt-dead".into(),
                payload: make_event(&pubkey_text, 101, 1),
                item_type: "event".into(),
            },
        ],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &batch)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    let body = cbor(&starling_wire::delete::DeleteEventsRequest {
        ids: vec!["evt-dead".into(), "evt-never-existed".into()],
    });
    let (status, recv) = send(&f.ctx, signed_delete(&f, "/events/delete", body.clone())).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(parse_delete_receipt(&recv), (1, 1));

    // Gone from the manifest…
    let (status, man) = send(&f.ctx, Request::get("/manifest").body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::OK);
    let (ids, _) = parse_manifest(&man);
    assert_eq!(ids, vec!["evt-keep"]);

    // …and from the /events envelope.
    let (status, ev) = send(&f.ctx, Request::get("/events").body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::OK);
    let env: Value = ciborium::from_reader(&ev[..]).unwrap();
    let items = env
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("items"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .len();
    assert_eq!(items, 1);

    // Replay the same delete: both ids now missing, still 200.
    let (status, recv) = send(&f.ctx, signed_delete(&f, "/events/delete", body)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(parse_delete_receipt(&recv), (0, 2));
}

/// Both delete routes refuse anonymous (401) and wrong-owner (403)
/// requests.
#[tokio::test]
async fn delete_routes_auth_matrix() {
    let f = fixture();
    let ev_body = cbor(&starling_wire::delete::DeleteEventsRequest { ids: vec!["e".into()] });
    let md_body = cbor(&starling_wire::delete::DeleteMediaRequest {
        hashes: vec!["a".repeat(64)],
    });

    for (path, body) in [("/events/delete", &ev_body), ("/media/delete", &md_body)] {
        // Anonymous → 401.
        let (status, _) = send(
            &f.ctx,
            Request::post(path).body(Body::from(body.clone())).unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{path} anonymous");

        // Valid signature by a DIFFERENT owner → 403.
        let other_sk = SigningKey::from_bytes(&[9u8; 32]);
        let ts = starling_wire::now_secs();
        let digest = starling_wire::owner_request_digest("POST", path, ts, body);
        let sig = other_sk.sign(&digest);
        let (status, _) = send(
            &f.ctx,
            Request::post(path)
                .header("x-starling-pubkey", b64(&other_sk.verifying_key().to_bytes()))
                .header("x-starling-sig", b64(&sig.to_bytes()))
                .header("x-starling-ts", ts.to_string())
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{path} wrong owner");
    }
}

/// Media delete removes the row, the blob file, and the manifest entry;
/// re-delete is idempotent; any malformed hash rejects the whole request.
#[tokio::test]
async fn media_delete_removes_row_file_and_manifest() {
    let f = fixture();
    let hash = "a".repeat(64);
    let blob = vec![7u8; 256];
    let (status, _) = send(&f.ctx, signed_media_push(&f, &hash, &blob)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let full = f.ctx.media_dir.join(owner_shard_path(&f.pubkey, &hash));
    assert!(full.exists());

    let body = cbor(&starling_wire::delete::DeleteMediaRequest {
        hashes: vec![hash.clone(), "b".repeat(64)],
    });
    let (status, recv) = send(&f.ctx, signed_delete(&f, "/media/delete", body.clone())).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(parse_delete_receipt(&recv), (1, 1));
    assert!(!full.exists(), "blob file unlinked");

    // Gone from /media-manifest.
    let (status, man) = send(&f.ctx, media_manifest_req(&f, None)).await;
    assert_eq!(status, StatusCode::OK);
    let page: Value = ciborium::from_reader(&man[..]).unwrap();
    let hashes = page
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some("hashes"))
        .and_then(|(_, v)| v.as_array())
        .unwrap()
        .len();
    assert_eq!(hashes, 0);

    // GET now 404s.
    let (status, _) = send(
        &f.ctx,
        Request::get(format!("/media/{hash}")).body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Idempotent replay.
    let (status, recv) = send(&f.ctx, signed_delete(&f, "/media/delete", body)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(parse_delete_receipt(&recv), (0, 2));

    // A single malformed hash 400s the whole request.
    let bad = cbor(&starling_wire::delete::DeleteMediaRequest {
        hashes: vec!["not-a-hash".into()],
    });
    let (status, _) = send(&f.ctx, signed_delete(&f, "/media/delete", bad)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

/// The whole point of pruning: a 507'd Owner deletes old events and the
/// next push fits (delete frees cap).
#[tokio::test]
async fn delete_frees_cap_507_then_202() {
    let f = fixture_with(Caps::default(), Some(1000));
    let pubkey_text = crockford_base32_encode(&f.pubkey);

    let old = PushBatch {
        items: vec![PushItem {
            id: "evt-old".into(),
            payload: make_event_sized(&pubkey_text, 100, 0, 800),
            item_type: "event".into(),
        }],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &old)).await;
    assert_eq!(status, StatusCode::ACCEPTED);

    let new = PushBatch {
        items: vec![PushItem {
            id: "evt-new".into(),
            payload: make_event_sized(&pubkey_text, 200, 1, 700),
            item_type: "event".into(),
        }],
    };
    let (status, _) = send(&f.ctx, signed_events_push(&f, &new)).await;
    assert_eq!(status, StatusCode::INSUFFICIENT_STORAGE);

    let body = cbor(&starling_wire::delete::DeleteEventsRequest {
        ids: vec!["evt-old".into()],
    });
    let (status, recv) = send(&f.ctx, signed_delete(&f, "/events/delete", body)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(parse_delete_receipt(&recv), (1, 0));

    let (status, _) = send(&f.ctx, signed_events_push(&f, &new)).await;
    assert_eq!(status, StatusCode::ACCEPTED);
}

// ---------------------------------------------------------------------------
// Wire unpair (A3): POST /unpair
// ---------------------------------------------------------------------------

/// `/unpair` auth matrix: anonymous → 401, a valid signature by a
/// DIFFERENT owner → 403 — and in both cases the supervisor hook must NOT
/// fire. With no hook wired (test/bare contexts) a valid owner signature
/// answers 501 instead of silently pretending to unpair.
#[tokio::test]
async fn unpair_auth_matrix_and_unwired_501() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    let mut f = fixture();
    let fired = Arc::new(AtomicUsize::new(0));
    let fired_in_hook = fired.clone();
    f.ctx.unpair = Some(Arc::new(move || {
        fired_in_hook.fetch_add(1, Ordering::SeqCst);
    }) as starling_relay_http::UnpairHandle);

    // Anonymous → 401.
    let (status, _) = send(
        &f.ctx,
        Request::post("/unpair").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "anonymous");

    // Valid signature by a DIFFERENT owner → 403.
    let other_sk = SigningKey::from_bytes(&[9u8; 32]);
    let ts = starling_wire::now_secs();
    let digest = starling_wire::owner_request_digest("POST", "/unpair", ts, &[]);
    let sig = other_sk.sign(&digest);
    let (status, _) = send(
        &f.ctx,
        Request::post("/unpair")
            .header("x-starling-pubkey", b64(&other_sk.verifying_key().to_bytes()))
            .header("x-starling-sig", b64(&sig.to_bytes()))
            .header("x-starling-ts", ts.to_string())
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "wrong owner");
    assert_eq!(fired.load(Ordering::SeqCst), 0, "hook never fired unauthorized");

    // The real owner → 200 + exactly one hook invocation.
    let (status, _) = send(&f.ctx, signed_delete(&f, "/unpair", Vec::new())).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(fired.load(Ordering::SeqCst), 1, "hook fired once");

    // No hook wired → 501, never a phantom success.
    f.ctx.unpair = None;
    let (status, _) = send(&f.ctx, signed_delete(&f, "/unpair", Vec::new())).await;
    assert_eq!(status, StatusCode::NOT_IMPLEMENTED);
}
