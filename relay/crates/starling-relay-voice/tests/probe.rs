//! Minimal diagnostic probe: one client, one server session, no
//! renegotiation. Bisects whether the basic mic path is reliable.

use std::time::{Duration, Instant};

mod common;
use common::{pump, pump_until_connected, slot, start_server, TestClient};

const OWNER: [u8; 32] = [0x33; 32];
const TOKEN: [u8; 32] = [0x44; 32];

#[tokio::test(flavor = "multi_thread")]
async fn single_client_mic_reaches_server() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN, None)]).await;

    for round in 0..5 {
        let mut a = TestClient::join(&handle, OWNER, &TOKEN).await;
        pump_until_connected(&mut [&mut a]).await;

        let before = a.rtp_tx_count;
        for i in 0..5u8 {
            a.send_audio(&[i; 60]);
            pump(&mut [&mut a], 3).await;
        }
        let deadline = Instant::now() + Duration::from_secs(5);
        while a.rtp_tx_count < before + 5 {
            assert!(
                Instant::now() < deadline,
                "round {round}: client emitted only {} of 5 RTP packets",
                a.rtp_tx_count - before
            );
            pump(&mut [&mut a], 5).await;
        }
        a.leave().await;
        pump(&mut [&mut a], 5).await;
    }
}
