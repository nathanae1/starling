//! `GET /ws/voice` — the SFU signaling socket, served on each Owner's
//! onion router (the supervisor merges this router into the per-owner
//! axum server; Arti's reverse proxy is a plain TCP proxy, so the WS
//! upgrade tunnels through unchanged).
//!
//! The adapter is deliberately thin: binary CBOR frames ↔
//! [`ClientFrame`]/[`ServerFrame`], first frame must be `join{token}`
//! within [`JOIN_DEADLINE`], and a dropped socket counts as leaving. All
//! call logic lives in the event loop behind [`VoiceHandle`].

use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::Response;
use axum::routing::get;
use axum::Router;
use starling_relay_http::{rate_limit_mw, RateLimiter};
use starling_wire::voice::{ClientFrame, ServerFrame, ERR_PROTOCOL};

use crate::VoiceHandle;

/// The token must arrive promptly — an idle pre-join socket holds a
/// session slot for nothing.
const JOIN_DEADLINE: Duration = Duration::from_secs(10);

/// SDP-sized signaling; anything bigger is not ours.
const MAX_FRAME_BYTES: usize = 64 * 1024;

/// Anonymous joins are human-paced; this bucket only has to stop floods.
const WS_RATE_PER_MIN: u32 = 30;
const WS_BURST: u32 = 10;

#[derive(Clone)]
struct WsCtx {
    handle: VoiceHandle,
    owner: [u8; 32],
}

/// Build the `/ws/voice` router for one Owner. Token-authed (the first
/// frame carries the room-token preimage) — no Ed25519 anywhere on this
/// path, participants stay pseudonymous.
pub fn voice_ws_router(handle: VoiceHandle, owner: [u8; 32]) -> Router {
    Router::new()
        .route("/ws/voice", get(upgrade_handler))
        .layer(axum::middleware::from_fn_with_state(
            RateLimiter::per_minute(WS_RATE_PER_MIN, WS_BURST),
            rate_limit_mw,
        ))
        .with_state(WsCtx { handle, owner })
}

async fn upgrade_handler(State(ctx): State<WsCtx>, ws: WebSocketUpgrade) -> Response {
    ws.max_message_size(MAX_FRAME_BYTES)
        .on_upgrade(move |socket| drive(socket, ctx))
}

async fn drive(mut socket: WebSocket, ctx: WsCtx) {
    // First frame: join{token}, on a deadline.
    let first = match tokio::time::timeout(JOIN_DEADLINE, next_frame(&mut socket)).await {
        Ok(Some(frame)) => frame,
        Ok(None) | Err(_) => return, // closed or silent — nothing to clean up
    };
    if !matches!(first, ClientFrame::Join { .. }) {
        let err = ServerFrame::Error {
            code: ERR_PROTOCOL.to_string(),
            message: "first frame must be join".to_string(),
        };
        let _ = socket.send(Message::Binary(err.to_cbor())).await;
        return;
    }
    let Some(mut session) = ctx.handle.open_session(ctx.owner).await else {
        return; // voice event loop gone (shutdown)
    };
    session.tx.frame(first).await;

    loop {
        tokio::select! {
            msg = socket.recv() => match msg {
                Some(Ok(Message::Binary(bytes))) => match ClientFrame::parse(&bytes) {
                    Some(frame) => session.tx.frame(frame).await,
                    None => break, // garbage — closing counts as leave
                },
                Some(Ok(Message::Close(_))) | None => break,
                Some(Ok(_)) => {} // text/ping/pong — axum answers pings itself
                Some(Err(_)) => break,
            },
            frame = session.rx.recv() => match frame {
                Some(frame) => {
                    if socket.send(Message::Binary(frame.to_cbor())).await.is_err() {
                        break;
                    }
                }
                // Session over (error/full/bye already delivered above).
                None => break,
            },
        }
    }
    // Explicit leave; the SessionTx drop-guard also covers panics.
    session.tx.close().await;
}

async fn next_frame(socket: &mut WebSocket) -> Option<ClientFrame> {
    while let Some(msg) = socket.recv().await {
        match msg {
            Ok(Message::Binary(bytes)) => return ClientFrame::parse(&bytes),
            Ok(Message::Close(_)) | Err(_) => return None,
            Ok(_) => continue,
        }
    }
    None
}
