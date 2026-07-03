//! Unix-socket control channel for the `starling-relay pair` CLI.
//!
//! The running `serve` process listens on `${data_dir}/admin.sock` (mode
//! 0600). The CLI connects, sends one JSON request line, reads one JSON
//! response line. This lets an SSH user mint a pairing token without the
//! web UI.

use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use starling_relay_admin::mint_pairing_token;
use starling_relay_storage::Db;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Request {
    Pair { label: Option<String> },
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Response {
    Ok { pair_url: String, expires_at: i64 },
    Error { message: String },
}

/// Server side: bind the socket and serve requests until the process exits.
pub async fn serve(
    path: PathBuf,
    db: Db,
    admin_onion: String,
    relay_version: String,
    ttl_secs: i64,
) -> Result<()> {
    // Replace any stale socket from a previous run.
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)
        .with_context(|| format!("bind admin socket {}", path.display()))?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
        .context("chmod admin socket 0600")?;

    loop {
        let (stream, _) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                log::warn!("admin socket accept failed: {e}");
                continue;
            }
        };
        let db = db.clone();
        let admin_onion = admin_onion.clone();
        let relay_version = relay_version.clone();
        tokio::spawn(async move {
            if let Err(e) =
                handle_conn(stream, db, admin_onion, relay_version, ttl_secs).await
            {
                log::debug!("admin socket conn ended: {e:?}");
            }
        });
    }
}

async fn handle_conn(
    stream: UnixStream,
    db: Db,
    admin_onion: String,
    relay_version: String,
    ttl_secs: i64,
) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    let resp = match serde_json::from_str::<Request>(line.trim()) {
        Ok(Request::Pair { label }) => {
            let minted = db
                .run(move |conn| {
                    mint_pairing_token(conn, &admin_onion, &relay_version, label, ttl_secs, "cli")
                })
                .await;
            match minted {
                Ok(m) => Response::Ok {
                    pair_url: m.pair_url,
                    expires_at: m.expires_at,
                },
                Err(e) => Response::Error {
                    message: e.to_string(),
                },
            }
        }
        Err(e) => Response::Error {
            message: format!("bad request: {e}"),
        },
    };
    let mut out = serde_json::to_string(&resp)?;
    out.push('\n');
    reader.into_inner().write_all(out.as_bytes()).await?;
    Ok(())
}

/// Client side: send one request, await the response.
pub async fn request(path: &PathBuf, req: &Request) -> Result<Response> {
    let stream = UnixStream::connect(path)
        .await
        .with_context(|| format!("connect admin socket {} (is the relay running?)", path.display()))?;
    let mut reader = BufReader::new(stream);
    let mut payload = serde_json::to_string(req)?;
    payload.push('\n');
    reader.get_mut().write_all(payload.as_bytes()).await?;
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    Ok(serde_json::from_str(line.trim())?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    struct Fixture {
        sock: PathBuf,
        _dir: tempfile::TempDir,
        server: tokio::task::JoinHandle<()>,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            self.server.abort();
        }
    }

    /// Boot a serve() loop on a tempdir socket and wait until it accepts.
    async fn fixture() -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        let sock = dir.path().join("admin.sock");
        // Pre-create a stale socket file: serve() must replace it, not fail.
        std::fs::write(&sock, b"stale").unwrap();
        let db = Db::open_in_memory().unwrap();
        let server = {
            let sock = sock.clone();
            tokio::spawn(async move {
                let _ = serve(
                    sock,
                    db,
                    "adminexample.onion".to_string(),
                    "0.1.0-test".to_string(),
                    600,
                )
                .await;
            })
        };
        for _ in 0..100 {
            if UnixStream::connect(&sock).await.is_ok() {
                return Fixture { sock, _dir: dir, server };
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("admin socket never came up");
    }

    /// The CLI round-trip: one JSON line in, one JSON line out, token
    /// minted against the DB with the admin onion in the pair URL.
    #[tokio::test]
    async fn pair_request_mints_token() {
        let f = fixture().await;
        let before = starling_wire::now_secs();
        let resp = request(&f.sock, &Request::Pair { label: Some("ssh".into()) })
            .await
            .unwrap();
        match resp {
            Response::Ok { pair_url, expires_at } => {
                assert!(
                    pair_url.starts_with("starling-relay://pair?card="),
                    "pair URL shape: {pair_url}"
                );
                assert!(expires_at >= before + 590 && expires_at <= before + 610);
            }
            Response::Error { message } => panic!("unexpected error: {message}"),
        }
    }

    /// Garbage input gets a JSON error line, never a hangup or crash.
    #[tokio::test]
    async fn malformed_request_gets_error_response() {
        let f = fixture().await;
        let stream = UnixStream::connect(&f.sock).await.unwrap();
        let mut reader = BufReader::new(stream);
        reader
            .get_mut()
            .write_all(b"this is not json\n")
            .await
            .unwrap();
        let mut line = String::new();
        reader.read_line(&mut line).await.unwrap();
        let resp: Response = serde_json::from_str(line.trim()).unwrap();
        match resp {
            Response::Error { message } => assert!(message.contains("bad request")),
            Response::Ok { .. } => panic!("garbage must not mint a token"),
        }
    }

    /// The socket is 0600 — the pairing channel must not be usable by
    /// other local users.
    #[tokio::test]
    async fn socket_is_owner_only() {
        let f = fixture().await;
        let mode = std::fs::metadata(&f.sock).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600, "admin.sock mode {mode:o}");
    }
}
