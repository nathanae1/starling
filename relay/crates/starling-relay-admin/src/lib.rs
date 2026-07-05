//! Admin web UI + the onion-facing `/pair` handler.
//!
//! Two routers come out of this crate:
//! - [`admin_ui_router`] — bound to `bind_admin` (localhost by default).
//!   Lists Owners, mints pairing QRs, exposes `/api/owners` + `/health`.
//!   NEVER exposed over Tor.
//! - [`pair_router`] — just `POST /pair`, served on the admin `.onion` so a
//!   phone can complete pairing over Tor without reaching the admin UI.
//!
//! The actual onion-launching + per-Owner task management lives in the
//! binary; this crate calls back through the [`RelayControl`] trait.

use std::sync::Arc;

use askama::Template;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{Html, IntoResponse, Json, Response};
use axum::routing::{get, post};
use axum::Router;
use base64::Engine;
use bytes::Bytes;
use rand::RngCore;
use starling_relay_http::{internal, rate_limit_mw, RateLimiter};
use starling_relay_storage::{
    events, immediate_tx, media, owners, pairings, voice_slots, Connection, Db, PendingPairing,
};
use starling_wire::{crockford_base32_encode, now_secs};
use starling_wire::pairing::{
    compute_pair_claim, PairResponse, PairingClaimWire, RelayQrCard,
};

/// Callback into the binary's relay supervisor for onion lifecycle.
#[async_trait::async_trait]
pub trait RelayControl: Send + Sync {
    /// The admin onion address (bound into pairing claims).
    fn admin_onion(&self) -> String;

    /// Pair an Owner: allocate a loopback port, launch the per-Owner onion,
    /// persist the `paired_owners` row, and start serving. Returns
    /// `(relay_onion, relay_id)`. Idempotent if the Owner is already paired.
    async fn pair_owner(
        &self,
        owner_pubkey: [u8; 32],
        label: Option<String>,
    ) -> anyhow::Result<(String, String)>;

    /// Unpair an Owner: stop + unpublish the onion, then cascade-delete.
    async fn unpair_owner(&self, owner_pubkey: [u8; 32]) -> anyhow::Result<()>;

    /// `(serving, total)` owner-task counts for `/health`. Default `None`
    /// for implementations (e.g. test mocks) that run no serving tasks.
    async fn liveness(&self) -> Option<(usize, usize)> {
        None
    }

    /// Live (non-empty) voice-call counts per owner — aggregate only, no
    /// per-participant attribution (Plan 20). `None` = voice hosting
    /// disabled.
    async fn voice_overview(&self) -> Option<std::collections::HashMap<[u8; 32], usize>> {
        None
    }
}

#[derive(Clone)]
pub struct AdminState {
    pub db: Db,
    pub ctrl: Arc<dyn RelayControl>,
    pub relay_version: String,
    pub pairing_ttl_secs: i64,
    /// Fast path for [`basic_auth_mw`]: BLAKE2b-256 of the last password
    /// that passed argon2 verification, keyed to the PHC string it verified
    /// against (`set-password` rotates the PHC string, invalidating the
    /// entry). Without this the `/pair` page's 3-second `/api/owners` poll
    /// re-runs argon2id (~19 MiB, t=2) on every request.
    pub auth_cache: AuthCache,
}

pub type AuthCache = Arc<std::sync::Mutex<Option<(String, [u8; 32])>>>;

// ---------------------------------------------------------------------------
// Pairing-token minting (shared by the web UI and the CLI).
// ---------------------------------------------------------------------------

/// Result of minting a pending pairing token.
pub struct MintedToken {
    pub token: Vec<u8>,
    /// `starling-relay://pair?card=…` URL the phone scans.
    pub pair_url: String,
    pub expires_at: i64,
}

/// Insert a fresh single-use pending pairing token and build its QR URL.
/// Minting invalidates every prior unconsumed token: exactly one token is
/// claimable at a time, so a photographed QR dies as soon as the `/pair`
/// page re-mints (≤120 s auto-refresh).
pub fn mint_pairing_token(
    conn: &Connection,
    admin_onion: &str,
    relay_version: &str,
    label: Option<String>,
    ttl_secs: i64,
    created_by: &str,
) -> anyhow::Result<MintedToken> {
    let mut token = vec![0u8; 32];
    rand::thread_rng().fill_bytes(&mut token);
    let now = now_secs();
    let expires_at = now + ttl_secs;

    // One IMMEDIATE transaction: prune → consume-all → insert. Concurrent
    // mints (the web /pair auto-refresh racing a CLI `pair`) would otherwise
    // interleave consume/insert and leave two live tokens, breaking the
    // exactly-one-active-token invariant (M8).
    let tx = immediate_tx(conn)?;
    pairings::prune_expired(&tx, now).ok();
    pairings::consume_all_unconsumed(&tx, now)?;
    pairings::insert(
        &tx,
        &PendingPairing {
            token: token.clone(),
            created_at: now,
            expires_at,
            consumed_at: None,
            created_by: created_by.to_string(),
            label,
        },
    )?;
    tx.commit()?;

    let card = RelayQrCard {
        relay_onion: admin_onion.to_string(),
        pairing_token: token.clone(),
        relay_version: relay_version.to_string(),
    };
    let mut cbor = Vec::new();
    ciborium::into_writer(&card, &mut cbor)?;
    let b64 = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&cbor);
    let pair_url = format!("starling-relay://pair?card={b64}");

    Ok(MintedToken {
        token,
        pair_url,
        expires_at,
    })
}

// ---------------------------------------------------------------------------
// Routers
// ---------------------------------------------------------------------------

/// Admin UI (localhost). NOT served over Tor. When an `admin_credentials`
/// row exists (set via `starling-relay set-password`), every route requires
/// HTTP Basic auth — this is what makes binding to a LAN address safe.
pub fn admin_ui_router(state: AdminState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/pair", get(pair_page))
        .route("/health", get(health))
        .route("/api/owners", get(api_owners))
        .route("/api/unpair/:pubkey", post(api_unpair))
        .route_layer(axum::middleware::from_fn_with_state(
            state.clone(),
            basic_auth_mw,
        ))
        // Outermost (added last): rate-limit before the argon2 in
        // basic_auth_mw burns CPU. The /pair page polls /api/owners every
        // 3s (20/min), well inside the budget.
        .layer(axum::middleware::from_fn_with_state(
            RateLimiter::per_minute(120, 30),
            rate_limit_mw,
        ))
        .with_state(state)
}

/// Hash a password for storage (`set-password`).
pub fn hash_password(password: &str) -> anyhow::Result<String> {
    use argon2::password_hash::{rand_core::OsRng, PasswordHasher, SaltString};
    use argon2::Argon2;
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("argon2 hash: {e}"))?
        .to_string();
    Ok(hash)
}

fn verify_password(password: &str, stored_hash: &str) -> bool {
    use argon2::password_hash::{PasswordHash, PasswordVerifier};
    use argon2::Argon2;
    let Ok(parsed) = PasswordHash::new(stored_hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

/// CSRF guard for state-changing admin routes. Requires the custom
/// `X-Starling-Csrf` header — cross-origin pages can't set custom headers
/// without a CORS preflight, and this server never answers preflights — and
/// rejects browser-flagged cross-site requests outright.
fn csrf_ok(headers: &axum::http::HeaderMap) -> bool {
    headers.contains_key("x-starling-csrf") && !cross_site(headers)
}

/// True when the browser labeled the request cross-site (`Sec-Fetch-Site`).
/// Absent header (curl, old browsers, same-origin fetch) passes.
fn cross_site(headers: &axum::http::HeaderMap) -> bool {
    headers
        .get("sec-fetch-site")
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.eq_ignore_ascii_case("cross-site"))
}

async fn basic_auth_mw(
    State(st): State<AdminState>,
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> Response {
    // No credentials configured → open (localhost-only default).
    let stored = st
        .db
        .run(|conn| starling_relay_storage::creds::get(conn))
        .await
        .ok()
        .flatten();
    let Some(creds) = stored else {
        return next.run(req).await;
    };

    let supplied = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Basic "))
        .and_then(|b64| base64::engine::general_purpose::STANDARD.decode(b64).ok())
        .and_then(|raw| String::from_utf8(raw).ok())
        .and_then(|pair| pair.split_once(':').map(|(_, p)| p.to_string()));

    let verified = match supplied {
        Some(password) => verify_with_cache(&st, &password, &creds.password_hash).await,
        None => false,
    };

    if verified {
        next.run(req).await
    } else {
        (
            StatusCode::UNAUTHORIZED,
            [(
                axum::http::header::WWW_AUTHENTICATE,
                "Basic realm=\"Starling Relay\"",
            )],
            "authentication required",
        )
            .into_response()
    }
}

/// Check `password` against `stored_hash`, consulting the verified-password
/// cache first. A hit requires the cache entry to be keyed to the *current*
/// PHC string AND a constant-time digest match; only then is argon2 skipped.
/// A miss falls back to argon2 (off the runtime workers — argon2id is
/// ~19 MiB / tens of ms by design) and populates the cache on success.
async fn verify_with_cache(st: &AdminState, password: &str, stored_hash: &str) -> bool {
    use subtle::ConstantTimeEq;
    let digest = starling_wire::blake2b256(password.as_bytes());
    {
        let cache = st.auth_cache.lock().expect("auth cache lock");
        if let Some((phc, cached)) = &*cache {
            if phc == stored_hash && bool::from(digest.ct_eq(cached)) {
                return true;
            }
        }
    }
    let password = password.to_string();
    let hash = stored_hash.to_string();
    let ok = tokio::task::spawn_blocking(move || verify_password(&password, &hash))
        .await
        .unwrap_or(false);
    if ok {
        *st.auth_cache.lock().expect("auth cache lock") = Some((stored_hash.to_string(), digest));
    }
    ok
}

/// The onion-facing `/pair` endpoint (served on the admin `.onion`).
/// Tightly limited: pairing is a human-paced flow (scan QR, one claim,
/// maybe one timeout retry), and each attempt costs a sig verify.
pub fn pair_router(state: AdminState) -> Router {
    Router::new()
        .route("/pair", post(pair_post))
        .layer(axum::middleware::from_fn_with_state(
            RateLimiter::per_minute(10, 5),
            rate_limit_mw,
        ))
        .with_state(state)
}

// ---------------------------------------------------------------------------
// View models + templates
// ---------------------------------------------------------------------------

struct OwnerView {
    pubkey_short: String,
    label: String,
    onion: String,
    event_count: i64,
    media_used: i64,
    /// Aggregate voice cell ("off" / "on (2 slots, 1 active call)") — never
    /// per-participant detail, consistent with the dashboard rule.
    voice: String,
    pubkey_hex: String,
}

fn load_owner_views(
    conn: &Connection,
    voice_calls: Option<&std::collections::HashMap<[u8; 32], usize>>,
) -> anyhow::Result<Vec<OwnerView>> {
    let mut views = Vec::new();
    for o in owners::list(conn)? {
        let event_count = events::count(conn, &o.pubkey).unwrap_or(0);
        let media_used = media::total_bytes(conn, &o.pubkey).unwrap_or(0);
        let voice = match voice_calls {
            None => "off".to_string(),
            Some(calls) => {
                let slots = voice_slots::count_for_owner(conn, &o.pubkey).unwrap_or(0);
                let active = <[u8; 32]>::try_from(o.pubkey.as_slice())
                    .ok()
                    .and_then(|pk| calls.get(&pk).copied())
                    .unwrap_or(0);
                format!("on ({slots} slots, {active} active calls)")
            }
        };
        let pk32 = crockford_base32_encode(&o.pubkey);
        let short = pk32.chars().rev().take(8).collect::<String>();
        let short: String = short.chars().rev().collect();
        views.push(OwnerView {
            pubkey_short: format!("…{short}"),
            label: o.label.unwrap_or_default(),
            onion: o.relay_onion_address,
            event_count,
            media_used,
            voice,
            pubkey_hex: hex::encode(&o.pubkey),
        });
    }
    Ok(views)
}

#[derive(Template)]
#[template(
    source = r#"<!doctype html><html><head><meta charset="utf-8">
<title>Starling Relay</title>
<style>body{font-family:system-ui,sans-serif;max-width:780px;margin:2rem auto;padding:0 1rem;color:#222}
table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #ddd;font-size:.9rem}
.btn{display:inline-block;padding:.5rem .9rem;background:#2d6cdf;color:#fff;text-decoration:none;border-radius:6px}
.muted{color:#888;font-size:.8rem}code{font-family:ui-monospace,monospace}</style></head>
<body>
<h1>Starling Relay <span class="muted">v{{ relay_version }}</span></h1>
<p><a class="btn" href="/pair">+ Pair a phone</a></p>
{% if owners.is_empty() %}<p class="muted">No paired owners yet.</p>{% else %}
<table><thead><tr><th>Owner</th><th>Label</th><th>Onion</th><th>Events</th><th>Media</th><th>Voice</th><th></th></tr></thead>
<tbody>{% for o in owners %}<tr>
<td><code>{{ o.pubkey_short }}</code></td><td>{{ o.label }}</td>
<td class="muted"><code>{{ o.onion }}</code></td><td>{{ o.event_count }}</td>
<td>{{ o.media_used }}</td>
<td class="muted">{{ o.voice }}</td>
<td><button onclick="unpair('{{ o.pubkey_hex }}')">Unpair</button></td>
</tr>{% endfor %}</tbody></table>{% endif %}
<script>
async function unpair(pk){if(!confirm('Unpair and delete all stored data for this owner?'))return;
await fetch('/api/unpair/'+pk,{method:'POST',headers:{'X-Starling-Csrf':'1'}});location.reload();}
</script>
</body></html>"#,
    ext = "html"
)]
struct IndexTemplate {
    owners: Vec<OwnerView>,
    relay_version: String,
}

#[derive(Template)]
#[template(
    source = r#"<!doctype html><html><head><meta charset="utf-8">
<title>Pair a phone — Starling Relay</title>
<meta http-equiv="refresh" content="120">
<style>body{font-family:system-ui,sans-serif;max-width:520px;margin:2rem auto;padding:0 1rem;text-align:center;color:#222}
.qr{margin:1.2rem auto;width:300px}.muted{color:#888;font-size:.85rem}
code{font-family:ui-monospace,monospace;word-break:break-all;font-size:.75rem}</style></head>
<body>
<h1>Scan to pair</h1>
<div class="qr">{{ qr_svg|safe }}</div>
<p class="muted">Or open this link on the phone:</p>
<p><code>{{ pair_url }}</code></p>
<p class="muted">Expires in {{ ttl_secs }}s. This page auto-refreshes; you'll
return to the dashboard once pairing completes.</p>
<script>
const before=Date.now();
setInterval(async()=>{const r=await fetch('/api/owners');const j=await r.json();
if(j.length>{{ owner_count }}){location.href='/';}},3000);
</script>
</body></html>"#,
    ext = "html"
)]
struct PairTemplate {
    qr_svg: String,
    pair_url: String,
    ttl_secs: i64,
    owner_count: usize,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn index(State(st): State<AdminState>) -> Response {
    let voice_calls = st.ctrl.voice_overview().await;
    let owners = match st
        .db
        .run(move |conn| load_owner_views(conn, voice_calls.as_ref()))
        .await
    {
        Ok(o) => o,
        Err(e) => return internal(e),
    };
    let tmpl = IndexTemplate {
        owners,
        relay_version: st.relay_version.clone(),
    };
    match tmpl.render() {
        Ok(html) => Html(html).into_response(),
        Err(e) => internal(e.into()),
    }
}

async fn pair_page(
    State(st): State<AdminState>,
    headers: axum::http::HeaderMap,
) -> Response {
    // Minting invalidates the live token (see mint_pairing_token), so a
    // drive-by cross-site GET could otherwise kill the QR mid-pairing.
    if cross_site(&headers) {
        return (StatusCode::FORBIDDEN, "cross-site request rejected").into_response();
    }
    let admin_onion = st.ctrl.admin_onion();
    let relay_version = st.relay_version.clone();
    let ttl = st.pairing_ttl_secs;
    let minted = st
        .db
        .run(move |conn| {
            let minted =
                mint_pairing_token(conn, &admin_onion, &relay_version, None, ttl, "web")?;
            let owner_count = owners::list(conn).map(|v| v.len()).unwrap_or(0);
            Ok((minted, owner_count))
        })
        .await;
    let (minted, owner_count) = match minted {
        Ok(m) => m,
        Err(e) => return internal(e),
    };

    let qr_svg = match qrcode::QrCode::new(minted.pair_url.as_bytes()) {
        Ok(code) => code
            .render::<qrcode::render::svg::Color>()
            .min_dimensions(280, 280)
            .build(),
        Err(e) => return internal(anyhow::anyhow!("qr encode: {e}")),
    };
    let tmpl = PairTemplate {
        qr_svg,
        pair_url: minted.pair_url,
        ttl_secs: st.pairing_ttl_secs,
        owner_count,
    };
    match tmpl.render() {
        Ok(html) => Html(html).into_response(),
        Err(e) => internal(e.into()),
    }
}

async fn health(State(st): State<AdminState>) -> Response {
    let owner_count = st
        .db
        .run(|conn| owners::list(conn))
        .await
        .map(|v| v.len())
        .unwrap_or(0);
    let mut body = serde_json::json!({
        "status": "ok",
        "version": st.relay_version,
        "owner_count": owner_count,
    });
    // Per-Owner serving liveness (M5): `serving_owners < owner_count` flags
    // an owner whose listener is down while its onion is still published.
    if let Some((serving, total)) = st.ctrl.liveness().await {
        body["serving_owners"] = serving.into();
        body["degraded"] = (serving < total).into();
    }
    Json(body).into_response()
}

async fn api_owners(State(st): State<AdminState>) -> Response {
    let json = st
        .db
        .run(|conn| {
            let json: Vec<_> = owners::list(conn)?
                .into_iter()
                .map(|o| {
                    let count = events::count(conn, &o.pubkey).unwrap_or(0);
                    serde_json::json!({
                        "pubkey": crockford_base32_encode(&o.pubkey),
                        "label": o.label,
                        "onion": o.relay_onion_address,
                        "event_count": count,
                    })
                })
                .collect();
            Ok(json)
        })
        .await;
    match json {
        Ok(json) => Json(json).into_response(),
        Err(e) => internal(e),
    }
}

async fn api_unpair(
    State(st): State<AdminState>,
    axum::extract::Path(pubkey_hex): axum::extract::Path<String>,
    headers: axum::http::HeaderMap,
) -> Response {
    if !csrf_ok(&headers) {
        return (StatusCode::FORBIDDEN, "csrf check failed").into_response();
    }
    let Some(pk) = decode_hex32(&pubkey_hex) else {
        return (StatusCode::BAD_REQUEST, "bad pubkey").into_response();
    };
    match st.ctrl.unpair_owner(pk).await {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(e) => internal(e),
    }
}

/// `POST /pair` (onion-facing). See the module docs / `relay_pairing_initiator.dart`.
async fn pair_post(State(st): State<AdminState>, body: Bytes) -> Response {
    let claim: PairingClaimWire = match ciborium::from_reader(&body[..]) {
        Ok(c) => c,
        Err(_) => return (StatusCode::BAD_REQUEST, "malformed claim cbor").into_response(),
    };
    let pubkey = match base64::engine::general_purpose::STANDARD.decode(&claim.owner_pubkey) {
        Ok(p) => p,
        Err(_) => return (StatusCode::BAD_REQUEST, "bad owner_pubkey base64").into_response(),
    };
    let pubkey: [u8; 32] = match pubkey.try_into() {
        Ok(p) => p,
        Err(_) => return (StatusCode::BAD_REQUEST, "owner_pubkey not 32 bytes").into_response(),
    };

    // Verify the signed claim first — bound to the admin onion the QR
    // advertised. Everything below trusts the claim's pubkey.
    let digest = compute_pair_claim(&pubkey, &st.ctrl.admin_onion(), &claim.pairing_token);
    if !starling_wire::verify_ed25519(&pubkey, &digest, &claim.sig) {
        return (StatusCode::UNAUTHORIZED, "invalid signature").into_response();
    }

    let token = claim.pairing_token;
    let outcome = st
        .db
        .run(move |conn| {
            // Already-paired Owner retrying (e.g. the phone timed out
            // waiting for the first launch): skip the token entirely — the
            // sig proves key possession and `pair_owner` is idempotent,
            // returning the live onion.
            if owners::get(conn, &pubkey)?.is_some() {
                return Ok(TokenOutcome::Proceed(None));
            }

            let Some(pending) = pairings::get(conn, &token)? else {
                return Ok(TokenOutcome::Reject(StatusCode::UNAUTHORIZED, "unknown token"));
            };
            let now = now_secs();
            if pending.expires_at < now {
                return Ok(TokenOutcome::Reject(StatusCode::GONE, "token expired"));
            }
            // Atomic single-use claim, BEFORE the slow onion launch: exactly
            // one concurrent request wins the UPDATE. A launch failure below
            // burns the token — the `/pair` page auto-refreshes a fresh one.
            match pairings::mark_consumed(conn, &token, now)? {
                1 => Ok(TokenOutcome::Proceed(pending.label)),
                _ => Ok(TokenOutcome::Reject(StatusCode::CONFLICT, "token already used")),
            }
        })
        .await;
    let label = match outcome {
        Ok(TokenOutcome::Proceed(label)) => label,
        Ok(TokenOutcome::Reject(code, msg)) => return (code, msg).into_response(),
        Err(e) => return internal(e),
    };

    match st.ctrl.pair_owner(pubkey, label).await {
        Ok((relay_onion, relay_id)) => {
            let resp = PairResponse {
                relay_onion,
                relay_id,
            };
            let mut buf = Vec::new();
            ciborium::into_writer(&resp, &mut buf).expect("encode PairResponse");
            (
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "application/cbor")],
                buf,
            )
                .into_response()
        }
        Err(e) => {
            log::error!("pair_owner failed: {e:?}");
            (StatusCode::GATEWAY_TIMEOUT, "could not launch onion").into_response()
        }
    }
}

enum TokenOutcome {
    Proceed(Option<String>),
    Reject(StatusCode, &'static str),
}

fn decode_hex32(s: &str) -> Option<[u8; 32]> {
    hex::decode(s).ok()?.try_into().ok()
}
