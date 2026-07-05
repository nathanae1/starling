//! Phase A spike (Plan 20): prove the pure-Rust `rust-crypto` DTLS backend
//! works end-to-end — full ICE (client) against ICE-Lite (server), DTLS-SRTP
//! handshake, and byte-identical RTP payload exchange in RTP mode. This is
//! the go/no-go gate for building the SFU on str0m.

use std::net::SocketAddr;
use std::sync::Once;
use std::time::{Duration, Instant};

use str0m::format::Codec;
use str0m::media::{Direction, MediaKind};
use str0m::net::Receive;
use str0m::rtp::{RtpWrite, Ssrc};
use str0m::{Candidate, Event, Input, Output, Rtc};

fn install_crypto() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        str0m::crypto::from_feature_flags().install_process_default();
    });
}

struct Peer {
    rtc: Rtc,
    addr: SocketAddr,
    events: Vec<Event>,
    next_timeout: Instant,
}

impl Peer {
    fn new(mut rtc: Rtc, addr: SocketAddr, now: Instant) -> Self {
        rtc.add_local_candidate(Candidate::host(addr, "udp").unwrap())
            .unwrap();
        Peer { rtc, addr, events: Vec::new(), next_timeout: now }
    }
}

/// Poll one peer until it returns `Timeout`, queueing its Transmits.
fn poll_to_timeout(
    peer: &mut Peer,
    queue: &mut std::collections::VecDeque<(str0m::net::Protocol, SocketAddr, SocketAddr, Vec<u8>)>,
) {
    loop {
        match peer.rtc.poll_output().unwrap() {
            Output::Timeout(t) => {
                peer.next_timeout = t;
                break;
            }
            Output::Transmit(t) => {
                queue.push_back((t.proto, t.source, t.destination, t.contents.to_vec()));
            }
            Output::Event(e) => peer.events.push(e),
        }
    }
}

/// In-memory shuttle honouring the sans-IO contract: after every single
/// `Input::Receive` the receiving Rtc is polled to `Timeout` before it gets
/// the next datagram.
fn drive(peers: &mut [Peer], now: Instant) {
    let mut queue = std::collections::VecDeque::new();
    for peer in peers.iter_mut() {
        poll_to_timeout(peer, &mut queue);
    }
    while let Some((proto, source, destination, contents)) = queue.pop_front() {
        let Some(p) = peers.iter_mut().find(|p| p.addr == destination) else {
            continue;
        };
        let recv = Receive {
            proto,
            source,
            destination,
            contents: contents.as_slice().try_into().unwrap(),
        };
        p.rtc.handle_input(Input::Receive(now, recv)).unwrap();
        poll_to_timeout(p, &mut queue);
    }
}

/// Advance virtual time to the earliest pending timeout and let both peers
/// process it.
fn advance(peers: &mut [Peer], now: &mut Instant) {
    let next = peers.iter().map(|p| p.next_timeout).min().unwrap();
    *now = next.max(*now + Duration::from_millis(1));
    for p in peers.iter_mut() {
        p.rtc.handle_input(Input::Timeout(*now)).unwrap();
    }
    drive(peers, *now);
}

#[test]
fn dtls_handshake_and_rtp_exchange_with_rust_crypto() {
    install_crypto();

    let mut now = Instant::now();
    let client_addr: SocketAddr = "127.0.0.1:11000".parse().unwrap();
    let server_addr: SocketAddr = "127.0.0.1:22000".parse().unwrap();

    // Client = phone (full ICE); server = SFU (ICE-Lite, RTP mode).
    let client = Rtc::builder().set_rtp_mode(true).build(now);
    let server = Rtc::builder().set_ice_lite(true).set_rtp_mode(true).build(now);

    let mut client = Peer::new(client, client_addr, now);
    let mut server = Peer::new(server, server_addr, now);

    // Client offers a sendonly audio m-line (the SFU "one stream up" leg).
    let mut change = client.rtc.sdp_api();
    let mid = change.add_media(MediaKind::Audio, Direction::SendOnly, None, None, None);
    let (offer, pending) = change.apply().unwrap();
    let answer = server.rtc.sdp_api().accept_offer(offer).unwrap();
    client.rtc.sdp_api().accept_answer(pending, answer).unwrap();

    let mut peers = [client, server];
    let mut iters = 0;
    while !(peers[0].rtc.is_connected() && peers[1].rtc.is_connected()) {
        advance(&mut peers, &mut now);
        iters += 1;
        assert!(iters < 5000, "ICE+DTLS handshake did not complete");
    }

    // Send RTP with distinctive payloads; RTP mode means the server sees the
    // raw payload bytes (this is the SFU's forwarding input).
    let pt = peers[0]
        .rtc
        .codec_config()
        .find(|p| p.spec().codec == Codec::Opus)
        .map(|p| p.pt())
        .unwrap();
    // Adopt the m-line's SDP-created StreamTx (declaring a second stream on
    // the same mid makes str0m's by-mid send lookup nondeterministic).
    let ssrc: Ssrc = peers[0]
        .rtc
        .direct_api()
        .stream_tx_by_mid(mid, None)
        .expect("SDP-created stream for the offered m-line")
        .ssrc();

    let sent: Vec<Vec<u8>> = (0..10u8).map(|i| vec![i ^ 0x5a; 60 + i as usize]).collect();
    for (i, payload) in sent.iter().enumerate() {
        {
            let mut direct = peers[0].rtc.direct_api();
            let stream = direct.stream_tx(&ssrc).unwrap();
            stream.write_rtp(RtpWrite::new(
                pt,
                (i as u64 + 1).into(),
                (i as u32) * 960,
                now,
                payload.clone(),
            ));
        }
        for _ in 0..5 {
            advance(&mut peers, &mut now);
        }
    }
    for _ in 0..50 {
        advance(&mut peers, &mut now);
    }

    let received: Vec<Vec<u8>> = peers[1]
        .events
        .iter()
        .filter_map(|e| match e {
            Event::RtpPacket(p) => Some(p.payload.to_vec()),
            _ => None,
        })
        .collect();

    assert_eq!(received.len(), sent.len(), "every RTP packet must arrive");
    for (s, r) in sent.iter().zip(&received) {
        assert_eq!(s, r, "RTP payload must be byte-identical");
    }
}
