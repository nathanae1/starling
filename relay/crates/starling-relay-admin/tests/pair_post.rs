//! Integration tests for the `/pair` claim flow (S5: single-use tokens),
//! the admin UI CSRF guard (S6), and the Basic-auth verified-password
//! cache.

use std::sync::{Arc, Mutex};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use http_body_util::BodyExt;
use starling_relay_admin::{
    admin_ui_router, mint_pairing_token, pair_router, AdminState, RelayControl,
};
use starling_relay_storage::{owners, pairings, Db, PairedOwner, PendingPairing};
use starling_wire::pairing::{compute_pair_claim, PairingClaimWire};
use tower::ServiceExt; // oneshot

const ADMIN_ONION: &str = "adminexample.onion";

/// Mock supervisor. `pair_owner` optionally blocks on `gate` (signalling
/// `entered` first) so tests can hold a claim mid-"onion launch".
struct MockCtrl {
    entered: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    gate: Option<Arc<tokio::sync::Notify>>,
    unpaired: Mutex<Vec<[u8; 32]>>,
}

impl MockCtrl {
    fn instant() -> Self {
        MockCtrl {
            entered: Mutex::new(None),
            gate: None,
            unpaired: Mutex::new(Vec::new()),
        }
    }

    fn gated(entered: tokio::sync::oneshot::Sender<()>, gate: Arc<tokio::sync::Notify>) -> Self {
        MockCtrl {
            entered: Mutex::new(Some(entered)),
            gate: Some(gate),
            unpaired: Mutex::new(Vec::new()),
        }
    }
}

#[async_trait::async_trait]
impl RelayControl for MockCtrl {
    fn admin_onion(&self) -> String {
        ADMIN_ONION.to_string()
    }

    async fn pair_owner(
        &self,
        _owner_pubkey: [u8; 32],
        _label: Option<String>,
    ) -> anyhow::Result<(String, String)> {
        if let Some(tx) = self.entered.lock().unwrap().take() {
            tx.send(()).ok();
        }
        if let Some(gate) = &self.gate {
            gate.notified().await;
        }
        Ok(("ownerexample.onion".to_string(), "rid".to_string()))
    }

    async fn unpair_owner(&self, owner_pubkey: [u8; 32]) -> anyhow::Result<()> {
        self.unpaired.lock().unwrap().push(owner_pubkey);
        Ok(())
    }
}

fn state(ctrl: Arc<MockCtrl>) -> AdminState {
    AdminState {
        db: Db::open_in_memory().unwrap(),
        ctrl,
        relay_version: "test".to_string(),
        pairing_ttl_secs: 600,
        auth_cache: Default::default(),
    }
}

fn insert_token(db: &Db, token: &[u8]) {
    let conn = db.get().unwrap();
    pairings::insert(
        &conn,
        &PendingPairing {
            token: token.to_vec(),
            created_at: 1,
            expires_at: i64::MAX,
            consumed_at: None,
            created_by: "test".into(),
            label: None,
        },
    )
    .unwrap();
}

fn claim_body(sk: &SigningKey, token: &[u8]) -> Vec<u8> {
    let pubkey = sk.verifying_key().to_bytes();
    let digest = compute_pair_claim(&pubkey, ADMIN_ONION, token);
    let sig = sk.sign(&digest);
    let wire = PairingClaimWire {
        owner_pubkey: base64::engine::general_purpose::STANDARD.encode(pubkey),
        pairing_token: token.to_vec(),
        sig: sig.to_bytes().to_vec(),
    };
    let mut buf = Vec::new();
    ciborium::into_writer(&wire, &mut buf).unwrap();
    buf
}

fn pair_req(body: Vec<u8>) -> Request<Body> {
    Request::post("/pair")
        .header("content-type", "application/cbor")
        .body(Body::from(body))
        .unwrap()
}

/// D6: the pair router is tightly rate-limited (10/min, burst 5) — the 6th
/// rapid request 429s before any token/sig work.
#[tokio::test]
async fn pair_rate_limited_429() {
    let sk = SigningKey::from_bytes(&[5u8; 32]);
    let st = state(Arc::new(MockCtrl::instant()));
    let router = pair_router(st);
    let mut saw_429 = None;
    for i in 0..6 {
        let status = router
            .clone()
            .oneshot(pair_req(claim_body(&sk, &[9u8; 32])))
            .await
            .unwrap()
            .status();
        if status == StatusCode::TOO_MANY_REQUESTS {
            saw_429 = Some(i);
            break;
        }
        // Unknown token → 401 until the bucket runs dry.
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
    assert_eq!(saw_429, Some(5));
}

#[tokio::test]
async fn concurrent_claims_one_token_one_winner() {
    let sk = SigningKey::from_bytes(&[5u8; 32]);
    let (entered_tx, entered_rx) = tokio::sync::oneshot::channel();
    let gate = Arc::new(tokio::sync::Notify::new());
    let st = state(Arc::new(MockCtrl::gated(entered_tx, gate.clone())));
    let token = vec![1u8; 32];
    insert_token(&st.db, &token);
    let router = pair_router(st);

    // First claim: consumes the token, then parks inside the onion launch.
    let first = tokio::spawn({
        let router = router.clone();
        let body = claim_body(&sk, &token);
        async move { router.oneshot(pair_req(body)).await.unwrap().status() }
    });
    entered_rx.await.unwrap();

    // Second claim with the same token, while the first is still launching.
    let second = router
        .clone()
        .oneshot(pair_req(claim_body(&sk, &token)))
        .await
        .unwrap()
        .status();
    assert_eq!(second, StatusCode::CONFLICT);

    gate.notify_one();
    assert_eq!(first.await.unwrap(), StatusCode::OK);
}

#[tokio::test]
async fn minting_invalidates_prior_token() {
    let sk = SigningKey::from_bytes(&[5u8; 32]);
    let st = state(Arc::new(MockCtrl::instant()));
    let old = {
        let conn = st.db.get().unwrap();
        let old = mint_pairing_token(&conn, ADMIN_ONION, "test", None, 600, "web").unwrap();
        let _new = mint_pairing_token(&conn, ADMIN_ONION, "test", None, 600, "web").unwrap();
        old
    };

    let status = pair_router(st)
        .oneshot(pair_req(claim_body(&sk, &old.token)))
        .await
        .unwrap()
        .status();
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn already_paired_owner_retries_idempotently() {
    let sk = SigningKey::from_bytes(&[5u8; 32]);
    let pubkey = sk.verifying_key().to_bytes();
    let st = state(Arc::new(MockCtrl::instant()));
    {
        let conn = st.db.get().unwrap();
        owners::insert(
            &conn,
            &PairedOwner {
                pubkey: pubkey.to_vec(),
                label: None,
                paired_at: 1,
                relay_onion_address: "ownerexample.onion".into(),
                local_port: 17000,
                storage_cap_bytes: None,
            },
        )
        .unwrap();
    }
    // Token already consumed (e.g. by the first attempt that timed out
    // phone-side) — the retry must still succeed via the re-pair path.
    let token = vec![2u8; 32];
    insert_token(&st.db, &token);
    {
        let conn = st.db.get().unwrap();
        assert_eq!(pairings::mark_consumed(&conn, &token, 5).unwrap(), 1);
    }

    let resp = pair_router(st)
        .oneshot(pair_req(claim_body(&sk, &token)))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn bad_signature_rejected_before_token_lookup() {
    let sk = SigningKey::from_bytes(&[5u8; 32]);
    let st = state(Arc::new(MockCtrl::instant()));
    let token = vec![3u8; 32];
    insert_token(&st.db, &token);

    // Sign over a different token than the one carried in the claim.
    let mut body = claim_body(&sk, &[9u8; 32]);
    let mut wire: PairingClaimWire = ciborium::from_reader(&body[..]).unwrap();
    wire.pairing_token = token.clone();
    body.clear();
    ciborium::into_writer(&wire, &mut body).unwrap();

    let resp = pair_router(st.clone())
        .oneshot(pair_req(body))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    // The token must NOT have been burned by the failed attempt.
    let conn = st.db.get().unwrap();
    assert!(pairings::get(&conn, &token).unwrap().unwrap().consumed_at.is_none());
}

#[tokio::test]
async fn unpair_requires_csrf_header() {
    let ctrl = Arc::new(MockCtrl::instant());
    let st = state(ctrl.clone());
    let router = admin_ui_router(st);
    let pk_hex = "ab".repeat(32);

    // No CSRF header → 403, supervisor untouched.
    let resp = router
        .clone()
        .oneshot(
            Request::post(format!("/api/unpair/{pk_hex}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    assert!(ctrl.unpaired.lock().unwrap().is_empty());

    // Browser-flagged cross-site → 403 even with the header.
    let resp = router
        .clone()
        .oneshot(
            Request::post(format!("/api/unpair/{pk_hex}"))
                .header("x-starling-csrf", "1")
                .header("sec-fetch-site", "cross-site")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    assert!(ctrl.unpaired.lock().unwrap().is_empty());

    // Header present, same-origin → 204 and the unpair goes through.
    let resp = router
        .oneshot(
            Request::post(format!("/api/unpair/{pk_hex}"))
                .header("x-starling-csrf", "1")
                .header("sec-fetch-site", "same-origin")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);
    assert_eq!(ctrl.unpaired.lock().unwrap().len(), 1);
}

fn set_creds(db: &Db, password: &str) -> String {
    let hash = starling_relay_admin::hash_password(password).unwrap();
    let conn = db.get().unwrap();
    starling_relay_storage::creds::set(&conn, &hash, 1).unwrap();
    hash
}

fn authed_get(path: &str, password: &str) -> Request<Body> {
    let b64 = base64::engine::general_purpose::STANDARD.encode(format!("admin:{password}"));
    Request::get(path)
        .header("authorization", format!("Basic {b64}"))
        .body(Body::empty())
        .unwrap()
}

/// With a credentials row set, every admin route requires Basic auth; a
/// successful verify populates the verified-password cache.
#[tokio::test]
async fn basic_auth_required_when_creds_set() {
    let st = state(Arc::new(MockCtrl::instant()));
    set_creds(&st.db, "hunter2");
    let router = admin_ui_router(st.clone());

    let resp = router
        .clone()
        .oneshot(Request::get("/api/owners").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    let resp = router
        .clone()
        .oneshot(authed_get("/api/owners", "wrong"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    assert!(st.auth_cache.lock().unwrap().is_none());

    let resp = router
        .oneshot(authed_get("/api/owners", "hunter2"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(st.auth_cache.lock().unwrap().is_some());
}

/// The cache short-circuits argon2: a request succeeds via a pre-seeded
/// cache entry even though argon2 against the stored hash would REJECT the
/// password — proving the fast path is taken. Clearing the cache makes the
/// same request 401 (and a stale-PHC entry is ignored).
#[tokio::test]
async fn auth_cache_short_circuits_argon2() {
    let st = state(Arc::new(MockCtrl::instant()));
    // Stored hash verifies "other-password", NOT "polled".
    let phc = set_creds(&st.db, "other-password");
    let router = admin_ui_router(st.clone());

    *st.auth_cache.lock().unwrap() =
        Some((phc.clone(), starling_wire::blake2b256(b"polled")));
    let resp = router
        .clone()
        .oneshot(authed_get("/api/owners", "polled"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Same password, cold cache → falls through to argon2 → rejected.
    *st.auth_cache.lock().unwrap() = None;
    let resp = router
        .clone()
        .oneshot(authed_get("/api/owners", "polled"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);

    // Entry keyed to a rotated-away PHC string is ignored (set-password
    // invalidation).
    *st.auth_cache.lock().unwrap() =
        Some(("$argon2id$stale".to_string(), starling_wire::blake2b256(b"polled")));
    let resp = router
        .oneshot(authed_get("/api/owners", "polled"))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn cross_site_pair_page_rejected() {
    let st = state(Arc::new(MockCtrl::instant()));
    let router = admin_ui_router(st);

    let resp = router
        .clone()
        .oneshot(
            Request::get("/pair")
                .header("sec-fetch-site", "cross-site")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Normal navigation still mints + renders.
    let resp = router
        .oneshot(Request::get("/pair").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let html = resp.into_body().collect().await.unwrap().to_bytes();
    assert!(std::str::from_utf8(&html).unwrap().contains("starling-relay://pair?card="));
}
