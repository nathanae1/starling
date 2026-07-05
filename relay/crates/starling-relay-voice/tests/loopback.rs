//! In-process loopback tests: real UDP sockets, real DTLS-SRTP, the real
//! event loop — only the WS transport is skipped (sessions are driven via
//! `open_session`, exactly what the WS adapter does).

use std::time::{Duration, Instant};

use starling_wire::voice::{ERR_BAD_TOKEN, ERR_BUSY};

mod common;
use common::{pump, pump_until_connected, slot, start_server, TestClient};

const OWNER: [u8; 32] = [0x11; 32];
const TOKEN_A: [u8; 32] = [0xA1; 32];
const TOKEN_B: [u8; 32] = [0xB2; 32];

fn payloads(tag: u8, count: usize) -> Vec<Vec<u8>> {
    (0..count).map(|i| vec![tag ^ (i as u8); 40 + (i % 37)]).collect()
}

#[tokio::test(flavor = "multi_thread")]
async fn two_clients_byte_identical_forwarding() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, None)]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b]).await;
    assert_eq!(a.cap, 12);

    // Wait until both directions' downstream m-lines are negotiated.
    let deadline = Instant::now() + Duration::from_secs(10);
    while !(a.peer_mids.contains_key(&b.sfu_id) && b.peer_mids.contains_key(&a.sfu_id)) {
        assert!(Instant::now() < deadline, "peer m-lines not negotiated");
        pump(&mut [&mut a, &mut b], 5).await;
    }

    let sent_a = payloads(0x5a, 20);
    let sent_b = payloads(0x3c, 20);
    for i in 0..20 {
        a.send_audio(&sent_a[i]);
        b.send_audio(&sent_b[i]);
        pump(&mut [&mut a, &mut b], 3).await;
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    while b.received_from(&a.sfu_id).len() < 20 || a.received_from(&b.sfu_id).len() < 20 {
        assert!(
            Instant::now() < deadline,
            "forwarding incomplete: b got {}, a got {}",
            b.received_from(&a.sfu_id).len(),
            a.received_from(&b.sfu_id).len()
        );
        pump(&mut [&mut a, &mut b], 5).await;
    }

    // Byte-identical, in order — the forwarder has no transcode path.
    assert_eq!(b.received_from(&a.sfu_id), sent_a);
    assert_eq!(a.received_from(&b.sfu_id), sent_b);
}

#[tokio::test(flavor = "multi_thread")]
async fn third_participant_renegotiation_and_leave() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, None)]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b]).await;

    // Late joiner: existing participants renegotiate, newcomer sees both.
    let mut c = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b, &mut c]).await;
    assert_eq!(c.join_participants.len(), 2, "join_ack lists existing sfu_ids");

    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let done = a.peer_mids.contains_key(&c.sfu_id)
            && b.peer_mids.contains_key(&c.sfu_id)
            && c.peer_mids.contains_key(&a.sfu_id)
            && c.peer_mids.contains_key(&b.sfu_id);
        if done {
            break;
        }
        assert!(Instant::now() < deadline, "renegotiation did not converge");
        pump(&mut [&mut a, &mut b, &mut c], 5).await;
    }

    // All-pairs audio.
    let sent = payloads(0x77, 10);
    for p in &sent {
        c.send_audio(p);
        pump(&mut [&mut a, &mut b, &mut c], 3).await;
    }
    let deadline = Instant::now() + Duration::from_secs(10);
    while a.received_from(&c.sfu_id).len() < 10 || b.received_from(&c.sfu_id).len() < 10 {
        assert!(Instant::now() < deadline, "C's audio not fanned out");
        pump(&mut [&mut a, &mut b, &mut c], 5).await;
    }
    assert_eq!(a.received_from(&c.sfu_id), sent);
    assert_eq!(b.received_from(&c.sfu_id), sent);

    // Leave: the others hear about it.
    let b_id = b.sfu_id.clone();
    b.leave().await;
    let deadline = Instant::now() + Duration::from_secs(10);
    while !a.peers_left.contains(&b_id) || !c.peers_left.contains(&b_id) {
        assert!(Instant::now() < deadline, "PeerLeft not delivered");
        pump(&mut [&mut a, &mut c], 5).await;
    }

    // Remaining pair still forwards.
    let more = payloads(0x11, 5);
    for p in &more {
        a.send_audio(p);
        pump(&mut [&mut a, &mut c], 3).await;
    }
    let before = c.received_from(&a.sfu_id).len();
    let deadline = Instant::now() + Duration::from_secs(10);
    while c.received_from(&a.sfu_id).len() < before.max(5) {
        assert!(Instant::now() < deadline, "forwarding broke after leave");
        pump(&mut [&mut a, &mut c], 5).await;
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn cap_enforced_full() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, Some(2))]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b]).await;
    assert_eq!(a.cap, 2, "slot override lowers the cap");

    let mut c = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while !c.got_full {
        assert!(Instant::now() < deadline, "third join not rejected");
        pump(&mut [&mut a, &mut b, &mut c], 5).await;
    }
    assert!(c.session_closed || c.sfu_id.is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_token_rejected() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, None)]).await;

    let mut c = TestClient::join(&handle, OWNER, &[0xEE; 32]).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while c.last_error.is_none() {
        assert!(Instant::now() < deadline, "bad token not rejected");
        pump(&mut [&mut c], 5).await;
    }
    assert_eq!(c.last_error.as_ref().unwrap().0, ERR_BAD_TOKEN);

    // And the token is owner-scoped: right token, wrong owner.
    let mut d = TestClient::join(&handle, [0x22; 32], &TOKEN_A).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while d.last_error.is_none() {
        assert!(Instant::now() < deadline, "cross-owner token not rejected");
        pump(&mut [&mut d], 5).await;
    }
    assert_eq!(d.last_error.as_ref().unwrap().0, ERR_BAD_TOKEN);
}

#[tokio::test(flavor = "multi_thread")]
async fn slot_replace_applies_at_next_join() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, None)]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b]).await;

    // Rotate: replace the slot set (room key rotation pushes a new token).
    handle.register_slots(OWNER, vec![slot(&TOKEN_B, None)]).await;

    // Old token no longer admits.
    let mut c = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while c.last_error.is_none() {
        assert!(Instant::now() < deadline, "rotated-out token still admits");
        pump(&mut [&mut c], 5).await;
    }
    assert_eq!(c.last_error.as_ref().unwrap().0, ERR_BAD_TOKEN);

    // New token admits; the in-progress call is untouched (v1 semantics).
    let mut d = TestClient::join(&handle, OWNER, &TOKEN_B).await;
    pump_until_connected(&mut [&mut a, &mut b, &mut d]).await;
    assert!(a.last_error.is_none() && !a.got_bye, "existing call unaffected");
}

#[tokio::test(flavor = "multi_thread")]
async fn drop_owner_ends_live_calls_and_slots() {
    let handle = start_server(12, 4, Duration::from_secs(60)).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, None)]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a, &mut b]).await;
    assert_eq!(handle.overview().await.get(&OWNER), Some(&1));

    handle.drop_owner(OWNER).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while !(a.got_bye && b.got_bye) {
        assert!(Instant::now() < deadline, "unpair did not end the call");
        pump(&mut [&mut a, &mut b], 5).await;
    }
    assert!(handle.overview().await.is_empty());

    // Slots are gone with the owner.
    let mut c = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while c.last_error.is_none() {
        assert!(Instant::now() < deadline, "dropped owner's token still admits");
        pump(&mut [&mut c], 5).await;
    }
    assert_eq!(c.last_error.as_ref().unwrap().0, ERR_BAD_TOKEN);
}

#[tokio::test(flavor = "multi_thread")]
async fn max_concurrent_calls_busy() {
    let handle = start_server(12, 1, Duration::from_secs(60)).await;
    handle
        .register_slots(OWNER, vec![slot(&TOKEN_A, None), slot(&TOKEN_B, None)])
        .await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a]).await;

    let mut b = TestClient::join(&handle, OWNER, &TOKEN_B).await;
    let deadline = Instant::now() + Duration::from_secs(5);
    while b.last_error.is_none() {
        assert!(Instant::now() < deadline, "second call not rejected");
        pump(&mut [&mut a, &mut b], 5).await;
    }
    assert_eq!(b.last_error.as_ref().unwrap().0, ERR_BUSY);
}

/// The reap's observable effect: an empty call's frozen cap survives until
/// the reap fires, after which the next join re-reads the slot registry.
#[tokio::test(flavor = "multi_thread")]
async fn idle_reap_recomputes_call_cap() {
    let reap = Duration::from_millis(300);
    let handle = start_server(12, 4, reap).await;
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, Some(2))]).await;

    let mut a = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut a]).await;
    assert_eq!(a.cap, 2);
    a.leave().await;
    pump(&mut [&mut a], 5).await; // let the leave land; call is now empty

    // Raise the slot cap. Before the reap the old call object (cap 2) is
    // still in place; joining resurrects it with the frozen cap.
    handle.register_slots(OWNER, vec![slot(&TOKEN_A, Some(5))]).await;
    let mut b = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut b]).await;
    assert_eq!(b.cap, 2, "pre-reap join sees the frozen call cap");
    b.leave().await;
    pump(&mut [&mut b], 5).await;

    // After the reap the call is gone; a fresh join re-reads the registry.
    tokio::time::sleep(reap + Duration::from_millis(200)).await;
    let mut c = TestClient::join(&handle, OWNER, &TOKEN_A).await;
    pump_until_connected(&mut [&mut c]).await;
    assert_eq!(c.cap, 5, "post-reap join sees the new slot cap");
}
