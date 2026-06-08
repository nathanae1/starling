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
use starling_relay_storage::{events, media, owners, pairings, Db, PendingPairing};
use starling_wire::crockford_base32_encode;
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
}

#[derive(Clone)]
pub struct AdminState {
    pub db: Db,
    pub ctrl: Arc<dyn RelayControl>,
    pub relay_version: String,
    pub pairing_ttl_secs: i64,
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

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
pub fn mint_pairing_token(
    db: &Db,
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

    let conn = db.get()?;
    pairings::prune_expired(&conn, now).ok();
    pairings::insert(
        &conn,
        &PendingPairing {
            token: token.clone(),
            created_at: now,
            expires_at,
            consumed_at: None,
            created_by: created_by.to_string(),
            label,
        },
    )?;

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

async fn basic_auth_mw(
    State(st): State<AdminState>,
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> Response {
    // No credentials configured → open (localhost-only default).
    let stored = st
        .db
        .get()
        .ok()
        .and_then(|c| starling_relay_storage::creds::get(&c).ok().flatten());
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

    match supplied {
        Some(password) if verify_password(&password, &creds.password_hash) => next.run(req).await,
        _ => (
            StatusCode::UNAUTHORIZED,
            [(
                axum::http::header::WWW_AUTHENTICATE,
                "Basic realm=\"Starling Relay\"",
            )],
            "authentication required",
        )
            .into_response(),
    }
}

/// The onion-facing `/pair` endpoint (served on the admin `.onion`).
pub fn pair_router(state: AdminState) -> Router {
    Router::new()
        .route("/pair", post(pair_post))
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
    pubkey_hex: String,
}

fn load_owner_views(db: &Db) -> anyhow::Result<Vec<OwnerView>> {
    let conn = db.get()?;
    let mut views = Vec::new();
    for o in owners::list(&conn)? {
        let event_count = events::count(&conn, &o.pubkey).unwrap_or(0);
        let media_used = media::total_bytes(&conn, &o.pubkey).unwrap_or(0);
        let pk32 = crockford_base32_encode(&o.pubkey);
        let short = pk32.chars().rev().take(8).collect::<String>();
        let short: String = short.chars().rev().collect();
        views.push(OwnerView {
            pubkey_short: format!("…{short}"),
            label: o.label.unwrap_or_default(),
            onion: o.relay_onion_address,
            event_count,
            media_used,
            pubkey_hex: hex_encode(&o.pubkey),
        });
    }
    Ok(views)
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
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
<table><thead><tr><th>Owner</th><th>Label</th><th>Onion</th><th>Events</th><th>Media</th><th></th></tr></thead>
<tbody>{% for o in owners %}<tr>
<td><code>{{ o.pubkey_short }}</code></td><td>{{ o.label }}</td>
<td class="muted"><code>{{ o.onion }}</code></td><td>{{ o.event_count }}</td>
<td>{{ o.media_used }}</td>
<td><button onclick="unpair('{{ o.pubkey_hex }}')">Unpair</button></td>
</tr>{% endfor %}</tbody></table>{% endif %}
<script>
async function unpair(pk){if(!confirm('Unpair and delete all stored data for this owner?'))return;
await fetch('/api/unpair/'+pk,{method:'POST'});location.reload();}
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
    let owners = match load_owner_views(&st.db) {
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

async fn pair_page(State(st): State<AdminState>) -> Response {
    let minted = match mint_pairing_token(
        &st.db,
        &st.ctrl.admin_onion(),
        &st.relay_version,
        None,
        st.pairing_ttl_secs,
        "web",
    ) {
        Ok(m) => m,
        Err(e) => return internal(e),
    };
    let owner_count = st
        .db
        .get()
        .ok()
        .and_then(|c| owners::list(&c).ok())
        .map(|v| v.len())
        .unwrap_or(0);

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
        .get()
        .ok()
        .and_then(|c| owners::list(&c).ok())
        .map(|v| v.len())
        .unwrap_or(0);
    Json(serde_json::json!({
        "status": "ok",
        "version": st.relay_version,
        "owner_count": owner_count,
    }))
    .into_response()
}

async fn api_owners(State(st): State<AdminState>) -> Response {
    let conn = match st.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    let list = match owners::list(&conn) {
        Ok(l) => l,
        Err(e) => return internal(e),
    };
    let json: Vec<_> = list
        .into_iter()
        .map(|o| {
            let count = events::count(&conn, &o.pubkey).unwrap_or(0);
            serde_json::json!({
                "pubkey": crockford_base32_encode(&o.pubkey),
                "label": o.label,
                "onion": o.relay_onion_address,
                "event_count": count,
            })
        })
        .collect();
    Json(json).into_response()
}

async fn api_unpair(
    State(st): State<AdminState>,
    axum::extract::Path(pubkey_hex): axum::extract::Path<String>,
) -> Response {
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

    let conn = match st.db.get() {
        Ok(c) => c,
        Err(e) => return internal(e),
    };
    let pending = match pairings::get(&conn, &claim.pairing_token) {
        Ok(Some(p)) => p,
        Ok(None) => return (StatusCode::UNAUTHORIZED, "unknown token").into_response(),
        Err(e) => return internal(e),
    };
    let now = now_secs();
    if pending.consumed_at.is_some() {
        return (StatusCode::CONFLICT, "token already used").into_response();
    }
    if pending.expires_at < now {
        return (StatusCode::GONE, "token expired").into_response();
    }

    // Verify the signed claim — bound to the admin onion the QR advertised.
    let digest = compute_pair_claim(&pubkey, &st.ctrl.admin_onion(), &claim.pairing_token);
    if !starling_wire::verify_ed25519(&pubkey, &digest, &claim.sig) {
        return (StatusCode::UNAUTHORIZED, "invalid signature").into_response();
    }

    // Drop the pooled connection before the (possibly slow) onion launch.
    drop(conn);

    match st.ctrl.pair_owner(pubkey, pending.label.clone()).await {
        Ok((relay_onion, relay_id)) => {
            if let Ok(conn) = st.db.get() {
                pairings::mark_consumed(&conn, &claim.pairing_token, now).ok();
            }
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

fn decode_hex32(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}

fn internal(err: anyhow::Error) -> Response {
    log::error!("admin internal error: {err:?}");
    (StatusCode::INTERNAL_SERVER_ERROR, "internal error").into_response()
}
