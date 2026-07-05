//! HTTP-layer contract vectors: methods, paths, query-param names, auth
//! headers, and success status codes for every relay endpoint, pinned in
//! `app/starling/test/vectors/index.json` (`http` section) and asserted
//! here against the real router via axum oneshot. The Dart client mirror
//! is `test/vectors/http_vectors_test.dart`.
//!
//! Query params are asserted by EFFECT (a `?until_id=` filter must change
//! the result), not just by a 200 — serde ignores unknown params, so a
//! rename would otherwise still return 200 and pass.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use ciborium::value::Value as Cbor;
use ed25519_dalek::{Signer, SigningKey};
use http_body_util::BodyExt;
use serde_json::Value;
use starling_relay_http::{owner_router, Caps, OwnerCtx};
use starling_relay_storage::{owners, Db, PairedOwner, ServedEvent};
use tower::ServiceExt;

use base64::Engine;

fn vectors() -> Value {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../app/starling/test/vectors/index.json"
    );
    let text = std::fs::read_to_string(path).expect("read vectors index.json");
    serde_json::from_str(&text).expect("parse vectors json")
}

fn endpoint<'a>(v: &'a Value, name: &str) -> &'a Value {
    let e = &v["http"]["endpoints"][name];
    assert!(!e.is_null(), "http.endpoints.{name} missing from vectors");
    e
}

fn method(e: &Value) -> &str {
    e["method"].as_str().unwrap()
}

fn path(e: &Value) -> &str {
    e["path"].as_str().unwrap()
}

fn success(e: &Value) -> u16 {
    e["success_status"].as_u64().unwrap() as u16
}

fn query_names(e: &Value) -> Vec<&str> {
    e["query"]
        .as_array()
        .map(|a| a.iter().map(|q| q.as_str().unwrap()).collect())
        .unwrap_or_default()
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
                label: None,
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
        unpair: None,
        voice: None,
    };
    Fixture { sk, pubkey, ctx, _media: media }
}

fn insert_event(f: &Fixture, id: &str, created_at: i64) {
    let conn = f.ctx.db.get().unwrap();
    starling_relay_storage::events::insert(
        &conn,
        &ServedEvent {
            pubkey: f.pubkey.to_vec(),
            id: id.into(),
            created_at,
            msg_seq: 0,
            nonce: vec![0u8; 24],
            payload: vec![1u8; 4],
            item_type: "event".into(),
        },
    )
    .unwrap();
}

async fn send(ctx: &OwnerCtx, req: Request<Body>) -> (StatusCode, Vec<u8>) {
    let resp = owner_router(ctx.clone()).oneshot(req).await.unwrap();
    let status = resp.status();
    let body = resp.into_body().collect().await.unwrap().to_bytes().to_vec();
    (status, body)
}

/// Build a request signed with the bound scheme, using the header NAMES
/// pinned in the vectors' `http.auth_headers` — a renamed header fails
/// here before it fails in production.
fn signed(v: &Value, f: &Fixture, m: &str, sig_path: &str, uri: &str, body: Vec<u8>) -> Request<Body> {
    let names: Vec<&str> = v["http"]["auth_headers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|h| h.as_str().unwrap())
        .collect();
    assert_eq!(names, ["x-starling-pubkey", "x-starling-ts", "x-starling-sig"]);
    let ts = starling_wire::now_secs();
    let digest = starling_wire::owner_request_digest(m, sig_path, ts, &body);
    let sig = f.sk.sign(&digest);
    let b64 = base64::engine::general_purpose::STANDARD;
    Request::builder()
        .method(m)
        .uri(uri)
        .header(names[0], b64.encode(f.pubkey))
        .header(names[1], ts.to_string())
        .header(names[2], b64.encode(sig.to_bytes()))
        .body(Body::from(body))
        .unwrap()
}

fn cbor_map_field(body: &[u8], key: &str) -> Cbor {
    let v: Cbor = ciborium::from_reader(body).unwrap();
    v.as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .map(|(_, val)| val.clone())
        .unwrap_or(Cbor::Null)
}

fn manifest_ids(body: &[u8]) -> Vec<String> {
    cbor_map_field(body, "events")
        .as_array()
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
        .collect()
}

fn encode_cbor(v: &impl serde::Serialize) -> Vec<u8> {
    let mut buf = Vec::new();
    ciborium::into_writer(v, &mut buf).unwrap();
    buf
}

#[tokio::test]
async fn status_contract() {
    let v = vectors();
    let e = endpoint(&v, "status");
    let f = fixture();
    assert_eq!(method(e), "GET");
    let (status, body) = send(
        &f.ctx,
        Request::get(path(e)).body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status.as_u16(), success(e));
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert!(json["pubkey"].is_string());
}

/// `/manifest` query params by EFFECT: `since` bounds below, the
/// `(until, until_id)` keyset excludes the cursor row.
#[tokio::test]
async fn manifest_contract_params_have_effect() {
    let v = vectors();
    let e = endpoint(&v, "manifest");
    let f = fixture();
    insert_event(&f, "evtA", 100);
    insert_event(&f, "evtB", 200);
    let q = query_names(e);
    assert_eq!(q, ["since", "until", "until_id"]);

    let (status, body) = send(
        &f.ctx,
        Request::get(path(e)).body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status.as_u16(), success(e));
    assert_eq!(manifest_ids(&body), ["evtB", "evtA"]);

    let uri = format!("{}?{}=200", path(e), q[0]);
    let (_, body) = send(&f.ctx, Request::get(uri).body(Body::empty()).unwrap()).await;
    assert_eq!(manifest_ids(&body), ["evtB"], "since bounds below");

    let uri = format!("{}?{}=200&{}=evtB", path(e), q[1], q[2]);
    let (_, body) = send(&f.ctx, Request::get(uri).body(Body::empty()).unwrap()).await;
    assert_eq!(manifest_ids(&body), ["evtA"], "keyset cursor excludes evtB");
}

/// `GET /events` query params by EFFECT: the `(since, since_id)` keyset
/// resumes strictly after the cursor row.
#[tokio::test]
async fn events_get_contract_params_have_effect() {
    let v = vectors();
    let e = endpoint(&v, "events_get");
    let f = fixture();
    insert_event(&f, "evtA", 100);
    insert_event(&f, "evtB", 100);
    let q = query_names(e);
    assert_eq!(q, ["since", "since_id"]);

    let (status, body) = send(
        &f.ctx,
        Request::get(path(e)).body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status.as_u16(), success(e));
    let all = cbor_map_field(&body, "items").as_array().unwrap().len();
    assert_eq!(all, 2);

    let uri = format!("{}?{}=100&{}=evtA", path(e), q[0], q[1]);
    let (_, body) = send(&f.ctx, Request::get(uri).body(Body::empty()).unwrap()).await;
    let after = cbor_map_field(&body, "items").as_array().unwrap().len();
    assert_eq!(after, 1, "keyset cursor skips evtA");
}

/// Owner-signed write endpoints: correct method+path+headers succeed with
/// the pinned status; stripping the auth headers must NOT succeed. The
/// media_get read is checked between the pushes and the deletes.
#[tokio::test]
async fn signed_write_contracts() {
    let v = vectors();
    let f = fixture();
    let hash = "a".repeat(64);

    async fn check(v: &Value, f: &Fixture, hash: &str, name: &str, concrete: &str, body: Vec<u8>) {
        let e = endpoint(v, name);
        assert!(e["auth"].as_bool().unwrap(), "{name} is owner-signed");
        assert_eq!(path(e).replace("{hash}", hash), concrete, "{name} path template");

        // Unsigned → rejected, never the success status.
        let (status, _) = send(
            &f.ctx,
            Request::builder()
                .method(method(e))
                .uri(concrete)
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{name} unsigned");

        let req = signed(v, f, method(e), concrete, concrete, body);
        let (status, _) = send(&f.ctx, req).await;
        assert_eq!(status.as_u16(), success(e), "{name} signed");
    }

    let push_batch = starling_wire::push::PushBatch {
        items: vec![starling_wire::push::PushItem {
            id: "evt-http".into(),
            payload: vec![0xEE; 8],
            item_type: "opaque".into(),
        }],
    };
    check(&v, &f, &hash, "events_push", "/events", encode_cbor(&push_batch)).await;
    check(&v, &f, &hash, "media_push", &format!("/media/{hash}"), vec![7u8; 64]).await;

    // media_get while the blob exists.
    let e = endpoint(&v, "media_get");
    let concrete = path(e).replace("{hash}", &hash);
    let (status, body) = send(
        &f.ctx,
        Request::get(&concrete).body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status.as_u16(), success(e));
    assert_eq!(body, vec![7u8; 64]);

    let delete_events = starling_wire::delete::DeleteEventsRequest {
        ids: vec!["evt-http".into()],
    };
    let delete_media = starling_wire::delete::DeleteMediaRequest {
        hashes: vec![hash.clone()],
    };
    check(&v, &f, &hash, "events_delete", "/events/delete", encode_cbor(&delete_events)).await;
    check(&v, &f, &hash, "media_delete", "/media/delete", encode_cbor(&delete_media)).await;
}

/// `POST /unpair` is owner-signed: unsigned is rejected without firing
/// the supervisor hook; a signed request fires it and answers the pinned
/// status.
#[tokio::test]
async fn unpair_contract() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    let v = vectors();
    let e = endpoint(&v, "unpair");
    let mut f = fixture();
    assert!(e["auth"].as_bool().unwrap(), "unpair is owner-signed");
    let fired = Arc::new(AtomicBool::new(false));
    let fired_in_hook = fired.clone();
    f.ctx.unpair = Some(Arc::new(move || {
        fired_in_hook.store(true, Ordering::SeqCst);
    }) as starling_relay_http::UnpairHandle);

    let (status, _) = send(
        &f.ctx,
        Request::builder()
            .method(method(e))
            .uri(path(e))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "unsigned unpair");
    assert!(!fired.load(Ordering::SeqCst), "hook must not fire unsigned");

    let req = signed(&v, &f, method(e), path(e), path(e), Vec::new());
    let (status, _) = send(&f.ctx, req).await;
    assert_eq!(status.as_u16(), success(e), "signed unpair");
    assert!(fired.load(Ordering::SeqCst), "hook fired");
}

/// `/media-manifest` is owner-signed and its `after` param pages by
/// EFFECT.
#[tokio::test]
async fn media_manifest_contract() {
    let v = vectors();
    let e = endpoint(&v, "media_manifest");
    let f = fixture();
    let q = query_names(e);
    assert_eq!(q, ["after"]);

    for c in ["a", "b"] {
        let hash = c.repeat(64);
        let blob = vec![1u8; 16];
        let req = signed(
            &v,
            &f,
            "POST",
            &format!("/media/{hash}"),
            &format!("/media/{hash}"),
            blob,
        );
        let (status, _) = send(&f.ctx, req).await;
        assert_eq!(status, StatusCode::ACCEPTED);
    }

    let uri = format!("{}?{}={}", path(e), q[0], "a".repeat(64));
    let req = signed(&v, &f, method(e), path(e), &uri, Vec::new());
    let (status, body) = send(&f.ctx, req).await;
    assert_eq!(status.as_u16(), success(e));
    let hashes = cbor_map_field(&body, "hashes").as_array().unwrap().len();
    assert_eq!(hashes, 1, "after cursor excludes the first hash");
}

/// Plan 20: `POST /voice/rooms` — owner-sig gate, replace-the-set DB
/// effect, live-registry hook, receipt shape, and the disabled-404.
#[tokio::test]
async fn voice_rooms_contract() {
    use std::sync::{Arc, Mutex};

    use starling_relay_storage::voice_slots;
    use starling_wire::voice::{VoiceSlotEntry, VoiceSlotPush};

    let v = vectors();
    let e = endpoint(&v, "voice_rooms");
    assert_eq!(method(e), "POST");

    let mut f = fixture();
    let registrar_calls: Arc<Mutex<Vec<Vec<VoiceSlotEntry>>>> = Arc::default();
    let calls = registrar_calls.clone();
    f.ctx.voice = Some(starling_relay_http::VoiceCtx {
        max_participants: 12,
        registrar: Arc::new(move |slots| calls.lock().unwrap().push(slots)),
    });

    let push = VoiceSlotPush {
        slots: vec![
            VoiceSlotEntry { token_hash: vec![0xaa; 32], max_participants: Some(8) },
            VoiceSlotEntry { token_hash: vec![0xbb; 32], max_participants: None },
        ],
    };
    let body = encode_cbor(&push);

    // Unsigned → 401 before anything else happens.
    let req = Request::post(path(e)).body(Body::from(body.clone())).unwrap();
    let (status, _) = send(&f.ctx, req).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert!(registrar_calls.lock().unwrap().is_empty());

    // Signed → pinned success status + receipt, DB rows, registrar fired.
    let req = signed(&v, &f, method(e), path(e), path(e), body.clone());
    let (status, resp) = send(&f.ctx, req).await;
    assert_eq!(status.as_u16(), success(e));
    let slots = cbor_map_field(&resp, "slots");
    assert_eq!(slots.as_integer(), Some(2.into()));
    {
        let conn = f.ctx.db.get().unwrap();
        let rows = voice_slots::list_for_owner(&conn, &f.pubkey).unwrap();
        assert_eq!(rows.len(), 2);
    }
    assert_eq!(registrar_calls.lock().unwrap().len(), 1);

    // Replace-the-set: a smaller push deletes the missing slots.
    let replacement = VoiceSlotPush {
        slots: vec![VoiceSlotEntry { token_hash: vec![0xcc; 32], max_participants: None }],
    };
    let req = signed(&v, &f, method(e), path(e), path(e), encode_cbor(&replacement));
    let (status, _) = send(&f.ctx, req).await;
    assert_eq!(status.as_u16(), success(e));
    {
        let conn = f.ctx.db.get().unwrap();
        let rows = voice_slots::list_for_owner(&conn, &f.pubkey).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].token_hash, vec![0xcc; 32]);
    }

    // Validation: bad hash length and out-of-range caps → 400.
    let bad_hash = VoiceSlotPush {
        slots: vec![VoiceSlotEntry { token_hash: vec![0xaa; 16], max_participants: None }],
    };
    let req = signed(&v, &f, method(e), path(e), path(e), encode_cbor(&bad_hash));
    let (status, _) = send(&f.ctx, req).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let bad_cap = VoiceSlotPush {
        slots: vec![VoiceSlotEntry { token_hash: vec![0xaa; 32], max_participants: Some(24) }],
    };
    let req = signed(&v, &f, method(e), path(e), path(e), encode_cbor(&bad_cap));
    let (status, _) = send(&f.ctx, req).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "cap above the relay max is rejected");

    // /status reflects the enabled capability and the live slot count.
    let (status, body) = send(
        &f.ctx,
        Request::get("/status").body(Body::empty()).unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["voice"]["enabled"], Value::Bool(true));
    assert_eq!(json["voice"]["max_participants"], 12);
    assert_eq!(json["voice"]["slot_count"], 1);

    // Voice disabled → 404 on push, and /status reports enabled=false.
    let disabled = fixture();
    let req = signed(&v, &disabled, method(e), path(e), path(e), body);
    let (status, _) = send(&disabled.ctx, req).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, body) = send(
        &disabled.ctx,
        Request::get("/status").body(Body::empty()).unwrap(),
    )
    .await;
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["voice"]["enabled"], Value::Bool(false));
}
