//! `/ws/voice` adapter tests: a real axum server on a loopback port and a
//! real tokio-tungstenite client, pinned against the `ws_voice` entry in
//! the shared HTTP contract vectors.

use std::net::SocketAddr;
use std::time::Duration;

use futures::{SinkExt, StreamExt};
use starling_relay_voice::{voice_ws_router, VoiceHandle};
use starling_wire::voice::{ClientFrame, ServerFrame, ERR_BAD_TOKEN, ERR_PROTOCOL};
use tokio_tungstenite::tungstenite::Message;

mod common;
use common::{slot, start_server};

const OWNER: [u8; 32] = [0x55; 32];
const TOKEN: [u8; 32] = [0x66; 32];

fn ws_vector() -> (String, String) {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../app/starling/test/vectors/index.json"
    );
    let text = std::fs::read_to_string(path).expect("read vectors index.json");
    let v: serde_json::Value = serde_json::from_str(&text).expect("parse vectors json");
    let e = &v["http"]["endpoints"]["ws_voice"];
    assert!(!e.is_null(), "http.endpoints.ws_voice missing from vectors");
    assert_eq!(e["method"].as_str().unwrap(), "GET");
    assert_eq!(e["auth"].as_bool().unwrap(), false);
    assert_eq!(e["success_status"].as_u64().unwrap(), 101);
    (e["path"].as_str().unwrap().to_string(), "GET".to_string())
}

async fn serve_ws(handle: &VoiceHandle) -> SocketAddr {
    let router = voice_ws_router(handle.clone(), OWNER);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    addr
}

type WsClient = tokio_tungstenite::WebSocketStream<
    tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
>;

async fn connect(addr: SocketAddr, path: &str) -> WsClient {
    let (ws, resp) = tokio_tungstenite::connect_async(format!("ws://{addr}{path}"))
        .await
        .expect("ws connect");
    // The pinned success status: 101 Switching Protocols.
    assert_eq!(resp.status().as_u16(), 101);
    ws
}

async fn recv_frame(ws: &mut WsClient) -> Option<ServerFrame> {
    loop {
        match tokio::time::timeout(Duration::from_secs(5), ws.next()).await {
            Ok(Some(Ok(Message::Binary(bytes)))) => {
                return Some(ServerFrame::parse(&bytes).expect("parse server frame"));
            }
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) => return None,
            Ok(Some(Ok(_))) => continue,
            Ok(Some(Err(_))) | Err(_) => return None,
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn join_happy_path_gets_join_ack() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN, Some(5))]).await;
    let addr = serve_ws(&handle).await;
    let (path, _) = ws_vector();

    let mut ws = connect(addr, &path).await;
    ws.send(Message::Binary(ClientFrame::Join { token: TOKEN.to_vec() }.to_cbor()))
        .await
        .unwrap();
    match recv_frame(&mut ws).await {
        Some(ServerFrame::JoinAck { sfu_id, candidates, cap, participants }) => {
            assert_eq!(sfu_id.len(), 16);
            assert!(!candidates.is_empty(), "host candidates advertised");
            assert_eq!(cap, 5);
            assert!(participants.is_empty());
        }
        other => panic!("expected JoinAck, got {other:?}"),
    }

    // Clean leave: bye then close.
    ws.send(Message::Binary(ClientFrame::Bye {}.to_cbor())).await.unwrap();
    match recv_frame(&mut ws).await {
        Some(ServerFrame::Bye {}) | None => {}
        other => panic!("expected Bye/close, got {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_token_gets_error_and_close() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN, None)]).await;
    let addr = serve_ws(&handle).await;

    let mut ws = connect(addr, "/ws/voice").await;
    ws.send(Message::Binary(ClientFrame::Join { token: vec![0xEE; 32] }.to_cbor()))
        .await
        .unwrap();
    match recv_frame(&mut ws).await {
        Some(ServerFrame::Error { code, .. }) => assert_eq!(code, ERR_BAD_TOKEN),
        other => panic!("expected bad_token error, got {other:?}"),
    }
    assert!(recv_frame(&mut ws).await.is_none(), "socket closes after the error");
}

#[tokio::test(flavor = "multi_thread")]
async fn non_join_first_frame_is_protocol_error() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    let addr = serve_ws(&handle).await;

    let mut ws = connect(addr, "/ws/voice").await;
    ws.send(Message::Binary(ClientFrame::Offer { sdp: "v=0".into() }.to_cbor()))
        .await
        .unwrap();
    match recv_frame(&mut ws).await {
        Some(ServerFrame::Error { code, .. }) => assert_eq!(code, ERR_PROTOCOL),
        other => panic!("expected protocol error, got {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn upgrade_burst_hits_rate_limit() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    let addr = serve_ws(&handle).await;

    // The bucket allows a burst of 10; the 11th+ upgrade must 429 before
    // the websocket handshake completes.
    let mut rejected = 0;
    for _ in 0..15 {
        match tokio_tungstenite::connect_async(format!("ws://{addr}/ws/voice")).await {
            Ok((mut ws, _)) => {
                let _ = ws.close(None).await;
            }
            Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
                assert_eq!(resp.status().as_u16(), 429);
                rejected += 1;
            }
            Err(e) => panic!("unexpected ws error: {e}"),
        }
    }
    assert!(rejected >= 4, "burst beyond the bucket must be rejected, got {rejected}");
}
