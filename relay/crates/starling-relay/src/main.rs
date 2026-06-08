//! Starling headless relay binary. See `app/plans/15-headless-relay.md`.

mod admin_sock;
mod config;
mod supervisor;

use std::os::unix::fs::PermissionsExt;
use std::sync::Arc;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use config::Config;
use starling_arti::{ArtiNode, InitMode};
use starling_relay_admin::{admin_ui_router, hash_password, pair_router, AdminState, RelayControl};
use starling_relay_http::Caps;
use starling_relay_storage::{creds, Db};
use supervisor::Supervisor;
use tokio::net::TcpListener;

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Parser)]
#[command(name = "starling-relay", version = VERSION, about = "Starling headless relay")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run the relay (Tor + admin UI + per-Owner serving).
    Serve {
        #[arg(long)]
        config: Option<std::path::PathBuf>,
    },
    /// Mint a pairing token against a running relay (talks to admin.sock).
    Pair {
        #[arg(long)]
        config: Option<std::path::PathBuf>,
        #[arg(long)]
        label: Option<String>,
    },
    /// Create the database and run migrations, then exit.
    Migrate {
        #[arg(long)]
        config: Option<std::path::PathBuf>,
    },
    /// Set the admin UI password (read from stdin). Enables LAN exposure.
    SetPassword {
        #[arg(long)]
        config: Option<std::path::PathBuf>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Serve { config } => {
            let cfg = Config::load(config.as_deref())?;
            init_logger(&cfg.log_level);
            serve(cfg).await
        }
        Command::Pair { config, label } => {
            let cfg = Config::load(config.as_deref())?;
            cmd_pair(cfg, label).await
        }
        Command::Migrate { config } => {
            let cfg = Config::load(config.as_deref())?;
            ensure_dirs(&cfg)?;
            Db::open(&cfg.db_path())?;
            println!("migrated {}", cfg.db_path().display());
            Ok(())
        }
        Command::SetPassword { config } => {
            let cfg = Config::load(config.as_deref())?;
            ensure_dirs(&cfg)?;
            cmd_set_password(cfg)
        }
    }
}

fn init_logger(level: &str) {
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or(level.to_string()),
    )
    .init();
}

fn ensure_dirs(cfg: &Config) -> Result<()> {
    std::fs::create_dir_all(&cfg.data_dir)
        .with_context(|| format!("create data dir {}", cfg.data_dir.display()))?;
    // 0700 on the data dir — Arti's fs-mistrust (strict on the relay)
    // requires it, and the admin socket lives here.
    std::fs::set_permissions(&cfg.data_dir, std::fs::Permissions::from_mode(0o700)).ok();
    std::fs::create_dir_all(cfg.media_dir()).context("create media dir")?;
    std::fs::create_dir_all(cfg.arti_dir()).context("create arti dir")?;
    Ok(())
}

async fn serve(cfg: Config) -> Result<()> {
    ensure_dirs(&cfg)?;
    let db = Db::open(&cfg.db_path())?;

    log::info!("starting Tor (Arti) — this can take ~30s on first boot…");
    let arti = Arc::new(
        ArtiNode::start(cfg.arti_dir(), InitMode::Full, false)
            .await
            .context("start Arti")?,
    );

    // Admin onion → a loopback port serving ONLY the /pair route. The admin
    // UI itself is never exposed over Tor.
    let pair_listener = TcpListener::bind("127.0.0.1:0")
        .await
        .context("bind pair loopback listener")?;
    let pair_port = pair_listener.local_addr()?.port();
    let admin_onion_handle = arti
        .launch_service("starling-relay-admin", pair_port)
        .context("launch admin onion")?;
    let admin_onion = admin_onion_handle.address().to_string();
    log::info!("admin onion: http://{admin_onion}/pair");

    let caps = Caps {
        per_owner_default: cfg.per_owner_default_cap_bytes,
        disk_cap: cfg.disk_cap_bytes,
    };
    let supervisor = Arc::new(Supervisor::new(
        db.clone(),
        arti.clone(),
        cfg.media_dir(),
        caps,
        admin_onion.clone(),
        (cfg.local_port_range[0], cfg.local_port_range[1]),
    ));
    supervisor.restore_all().await?;

    let admin_state = AdminState {
        db: db.clone(),
        ctrl: supervisor.clone() as Arc<dyn RelayControl>,
        relay_version: VERSION.to_string(),
        pairing_ttl_secs: cfg.pairing_token_ttl_seconds,
    };

    // /pair over Tor.
    {
        let router = pair_router(admin_state.clone());
        tokio::spawn(async move {
            if let Err(e) = axum::serve(pair_listener, router).await {
                log::error!("pair router exited: {e}");
            }
        });
    }

    // Admin UI (localhost / LAN).
    let admin_listener = TcpListener::bind(&cfg.bind_admin)
        .await
        .with_context(|| format!("bind admin UI on {}", cfg.bind_admin))?;
    log::info!("admin UI: http://{}", cfg.bind_admin);
    {
        let router = admin_ui_router(admin_state.clone());
        tokio::spawn(async move {
            if let Err(e) = axum::serve(admin_listener, router).await {
                log::error!("admin UI exited: {e}");
            }
        });
    }

    // Unix-socket CLI control channel.
    {
        let sock = cfg.admin_sock();
        let db = db.clone();
        let admin_onion = admin_onion.clone();
        let ttl = cfg.pairing_token_ttl_seconds;
        tokio::spawn(async move {
            if let Err(e) =
                admin_sock::serve(sock, db, admin_onion, VERSION.to_string(), ttl).await
            {
                log::error!("admin socket exited: {e:?}");
            }
        });
    }

    log::info!("relay ready");
    wait_for_shutdown().await;
    log::info!("shutting down…");
    supervisor.shutdown_all().await;
    drop(admin_onion_handle);
    let _ = std::fs::remove_file(cfg.admin_sock());
    Ok(())
}

async fn cmd_pair(cfg: Config, label: Option<String>) -> Result<()> {
    let resp = admin_sock::request(&cfg.admin_sock(), &admin_sock::Request::Pair { label })
        .await
        .context("talk to running relay")?;
    match resp {
        admin_sock::Response::Ok {
            pair_url,
            expires_at,
        } => {
            println!("\nScan this with the Starling app:\n");
            print_qr(&pair_url);
            println!("\n{pair_url}\n");
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            println!("Expires in {}s.", (expires_at - now).max(0));
            Ok(())
        }
        admin_sock::Response::Error { message } => {
            anyhow::bail!("relay error: {message}")
        }
    }
}

fn cmd_set_password(cfg: Config) -> Result<()> {
    let db = Db::open(&cfg.db_path())?;
    eprint!("New admin password: ");
    use std::io::Write;
    std::io::stderr().flush().ok();
    let mut pw = String::new();
    std::io::stdin().read_line(&mut pw)?;
    let pw = pw.trim();
    if pw.is_empty() {
        anyhow::bail!("empty password");
    }
    let hash = hash_password(pw)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let conn = db.get()?;
    creds::set(&conn, &hash, now)?;
    println!("admin password set; admin UI now requires HTTP Basic auth.");
    Ok(())
}

fn print_qr(data: &str) {
    match qrcode::QrCode::new(data.as_bytes()) {
        Ok(code) => {
            let s = code
                .render::<qrcode::render::unicode::Dense1x2>()
                .quiet_zone(true)
                .build();
            println!("{s}");
        }
        Err(_) => println!("(could not render QR; use the URL below)"),
    }
}

async fn wait_for_shutdown() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = match signal(SignalKind::terminate()) {
            Ok(s) => s,
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
                return;
            }
        };
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
