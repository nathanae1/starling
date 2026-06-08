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
            match mint_pairing_token(&db, &admin_onion, &relay_version, label, ttl_secs, "cli") {
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
