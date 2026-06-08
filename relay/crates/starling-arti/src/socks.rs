//! In-process SOCKS5 listener (phone-only, behind the `socks` feature).
//!
//! Dart's `http.Client` connects to a kernel-assigned loopback port and we
//! tunnel each accepted TCP stream out through `TorClient::connect`. The
//! relay does not use this — it only serves inbound onion traffic.

use anyhow::{anyhow, Context, Result};
use tokio::io::{copy_bidirectional, AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tor_rtcompat::tokio::TokioRustlsRuntime;
use tor_socksproto::{
    Buffer, Handshake, NextStep, SocksAddr, SocksProxyHandshake, SocksStatus,
};

use arti_client::TorClient;

/// Bind a loopback SOCKS5 listener and spawn its accept loop. Returns the
/// chosen port plus the listener task handle.
pub(crate) async fn spawn_listener(
    client: TorClient<TokioRustlsRuntime>,
) -> Result<(u16, tokio::task::JoinHandle<()>)> {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .context("bind SOCKS5 listener")?;
    let port = listener
        .local_addr()
        .context("read SOCKS5 listener address")?
        .port();
    let task = tokio::spawn(run_listener(client, listener));
    Ok((port, task))
}

async fn run_listener(client: TorClient<TokioRustlsRuntime>, listener: TcpListener) {
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                log::warn!("socks accept failed: {e}");
                continue;
            }
        };
        let client = client.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_conn(stream, client).await {
                log::debug!("socks conn ended: {e:?}");
            }
        });
    }
}

async fn handle_conn(
    mut stream: TcpStream,
    client: TorClient<TokioRustlsRuntime>,
) -> Result<()> {
    let mut hs = SocksProxyHandshake::new();
    let mut buf = Buffer::new();

    let (request, leftover) = loop {
        match hs.step(&mut buf).map_err(|e| anyhow!("socks step: {e}"))? {
            NextStep::Send(data) => {
                stream.write_all(&data).await?;
            }
            NextStep::Recv(mut recv) => {
                let target = recv.buf();
                let n = stream.read(target).await?;
                if n == 0 {
                    return Err(anyhow!("client closed during SOCKS handshake"));
                }
                recv.note_received(n)
                    .map_err(|e| anyhow!("note_received: {e}"))?;
            }
            NextStep::Finished(fin) => {
                break fin.into_output_and_vec();
            }
        }
    };

    let (host, port) = match request.addr() {
        SocksAddr::Hostname(h) => (h.as_ref().to_string(), request.port()),
        SocksAddr::Ip(ip) => (ip.to_string(), request.port()),
    };

    let tor_stream = match client.connect((host.as_str(), port)).await {
        Ok(s) => s,
        Err(e) => {
            let reply = request
                .reply(SocksStatus::HOST_UNREACHABLE, None)
                .map_err(|err| anyhow!("build socks failure reply: {err}"))?;
            stream.write_all(&reply).await.ok();
            return Err(anyhow!("Tor connect to {host}:{port} failed: {e}"));
        }
    };

    let reply = request
        .reply(SocksStatus::SUCCEEDED, None)
        .map_err(|e| anyhow!("build socks success reply: {e}"))?;
    stream.write_all(&reply).await?;

    let mut tor_stream = tor_stream;
    if !leftover.is_empty() {
        tor_stream.write_all(&leftover).await?;
    }
    copy_bidirectional(&mut stream, &mut tor_stream).await?;
    Ok(())
}
