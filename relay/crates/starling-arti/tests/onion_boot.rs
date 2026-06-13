//! Network-gated smoke test (M2): bootstrap Arti and launch an onion
//! service. `#[ignore]` because it needs the live Tor network and takes
//! ~30s to bootstrap — run explicitly with:
//!
//!   cargo test -p starling-arti --test onion_boot -- --ignored --nocapture

use std::time::Duration;

use starling_arti::{ArtiNode, InitMode};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires live Tor network; ~30s bootstrap"]
async fn boots_and_launches_onion() {
    let dir = tempfile::tempdir().unwrap();
    let node = ArtiNode::start(dir.path().to_path_buf(), InitMode::Full, true)
        .await
        .expect("bootstrap arti");

    // A throwaway local listener for the reverse proxy target.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();

    let handle = node
        .launch_service("starling-test", port)
        .expect("launch onion service");
    let addr = handle.address();
    eprintln!("launched onion: {addr}");
    assert!(addr.ends_with(".onion"), "expected .onion, got {addr}");
}

/// Bind a local listener that answers every connection with `reply` and
/// return its port.
async fn spawn_echo_listener(reply: &'static [u8]) -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        loop {
            if let Ok((mut stream, _)) = listener.accept().await {
                let _ = stream.write_all(reply).await;
                let _ = stream.shutdown().await;
            }
        }
    });
    port
}

/// Minimal SOCKS5h CONNECT to `host:port` through the node's own SOCKS
/// listener (hostname resolved by the proxy, as .onion requires).
async fn socks_connect(socks_port: u16, host: &str, port: u16) -> std::io::Result<TcpStream> {
    let mut s = TcpStream::connect(("127.0.0.1", socks_port)).await?;
    s.write_all(&[0x05, 0x01, 0x00]).await?; // VER, 1 method, NO AUTH
    let mut buf = [0u8; 2];
    s.read_exact(&mut buf).await?;
    let mut req = vec![0x05, 0x01, 0x00, 0x03, host.len() as u8];
    req.extend_from_slice(host.as_bytes());
    req.extend_from_slice(&port.to_be_bytes());
    s.write_all(&req).await?;
    let mut head = [0u8; 4];
    s.read_exact(&mut head).await?;
    if head[1] != 0x00 {
        return Err(std::io::Error::other(format!("SOCKS reply {}", head[1])));
    }
    // Drain BND.ADDR + BND.PORT (ATYP from head[3]).
    let addr_len = match head[3] {
        0x01 => 4,
        0x04 => 16,
        0x03 => {
            let mut l = [0u8; 1];
            s.read_exact(&mut l).await?;
            l[0] as usize
        }
        other => return Err(std::io::Error::other(format!("SOCKS ATYP {other}"))),
    };
    let mut rest = vec![0u8; addr_len + 2];
    s.read_exact(&mut rest).await?;
    Ok(s)
}

/// Dial `addr:80` through our own SOCKS proxy and return the single reply
/// byte from whatever local listener the onion proxy forwards to.
async fn dial_onion_once(socks_port: u16, addr: &str) -> std::io::Result<u8> {
    let mut stream = tokio::time::timeout(
        Duration::from_secs(30),
        socks_connect(socks_port, addr, 80),
    )
    .await
    .map_err(|_| std::io::Error::other("socks connect timeout"))??;
    let mut byte = [0u8; 1];
    tokio::time::timeout(Duration::from_secs(20), stream.read_exact(&mut byte))
        .await
        .map_err(|_| std::io::Error::other("read timeout"))??;
    Ok(byte[0])
}

/// Retry [`dial_onion_once`] until it succeeds or `attempts` runs out —
/// a freshly published descriptor can take 1–2 minutes to reach the HSDirs.
async fn dial_onion_retry(socks_port: u16, addr: &str, attempts: u32) -> u8 {
    let mut last_err = None;
    for i in 0..attempts {
        match dial_onion_once(socks_port, addr).await {
            Ok(b) => return b,
            Err(e) => {
                eprintln!("dial attempt {i} failed: {e}");
                last_err = Some(e);
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
    panic!("onion never became dialable: {last_err:?}");
}

/// End-to-end check of [`OnionHandle::retarget`]: the same onion address
/// must forward to the *new* local port after a retarget, with no service
/// relaunch. This is the regression test for the lifecycle bug where the
/// app's HTTP server rebound on a new ephemeral port and the onion kept
/// forwarding to the dead old one.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires live Tor network; several minutes end-to-end"]
async fn retarget_moves_proxy_to_new_port() {
    let dir = tempfile::tempdir().unwrap();
    let node = ArtiNode::start(dir.path().to_path_buf(), InitMode::Full, true)
        .await
        .expect("bootstrap arti");

    let port_a = spawn_echo_listener(b"A").await;
    let port_b = spawn_echo_listener(b"B").await;

    let mut handle = node
        .launch_service("starling-retarget-test", port_a)
        .expect("launch onion service");
    let addr = handle.address().to_string();
    eprintln!("launched onion: {addr} -> 127.0.0.1:{port_a}");
    assert_eq!(handle.local_port(), port_a);

    let socks = node.socks_port();
    let first = dial_onion_retry(socks, &addr, 36).await;
    assert_eq!(first, b'A', "pre-retarget dial should reach listener A");

    handle.retarget(port_b).expect("retarget proxy");
    assert_eq!(handle.local_port(), port_b);
    eprintln!("retargeted onion -> 127.0.0.1:{port_b}");

    // New connections must hit B immediately — the proxy reads its config
    // per request. Allow transport-level retries, but a successful dial
    // must never reach A again.
    let second = dial_onion_retry(socks, &addr, 12).await;
    assert_eq!(second, b'B', "post-retarget dial should reach listener B");
}
