//! Network-gated smoke test (M2): bootstrap Arti and launch an onion
//! service. `#[ignore]` because it needs the live Tor network and takes
//! ~30s to bootstrap — run explicitly with:
//!
//!   cargo test -p starling-arti --test onion_boot -- --ignored --nocapture

use starling_arti::{ArtiNode, InitMode};

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
