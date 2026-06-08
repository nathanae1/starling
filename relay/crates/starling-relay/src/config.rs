//! Relay configuration: a TOML file overlaid with `STARLING_RELAY_*` env
//! vars. See `config.example.toml`.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Config {
    pub data_dir: PathBuf,
    pub bind_admin: String,
    pub disk_cap_bytes: i64,
    pub per_owner_default_cap_bytes: i64,
    pub log_level: String,
    pub pairing_token_ttl_seconds: i64,
    pub local_port_range: [u16; 2],
}

impl Default for Config {
    fn default() -> Self {
        Config {
            data_dir: PathBuf::from("/var/lib/starling-relay"),
            bind_admin: "127.0.0.1:8088".to_string(),
            disk_cap_bytes: 5 * 1024 * 1024 * 1024,
            per_owner_default_cap_bytes: 1024 * 1024 * 1024,
            log_level: "info".to_string(),
            pairing_token_ttl_seconds: 600,
            local_port_range: [17000, 17999],
        }
    }
}

impl Config {
    /// Load from `path` (if given) then apply env overrides.
    pub fn load(path: Option<&Path>) -> Result<Self> {
        let mut cfg = match path {
            Some(p) => {
                let text = std::fs::read_to_string(p)
                    .with_context(|| format!("read config {}", p.display()))?;
                toml::from_str(&text).with_context(|| format!("parse config {}", p.display()))?
            }
            None => Config::default(),
        };
        cfg.apply_env();
        Ok(cfg)
    }

    fn apply_env(&mut self) {
        if let Ok(v) = std::env::var("STARLING_RELAY_DATA_DIR") {
            self.data_dir = PathBuf::from(v);
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_BIND_ADMIN") {
            self.bind_admin = v;
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_LOG_LEVEL") {
            self.log_level = v;
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_DISK_CAP_BYTES") {
            if let Ok(n) = v.parse() {
                self.disk_cap_bytes = n;
            }
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_PER_OWNER_DEFAULT_CAP_BYTES") {
            if let Ok(n) = v.parse() {
                self.per_owner_default_cap_bytes = n;
            }
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_PAIRING_TOKEN_TTL_SECONDS") {
            if let Ok(n) = v.parse() {
                self.pairing_token_ttl_seconds = n;
            }
        }
    }

    pub fn db_path(&self) -> PathBuf {
        self.data_dir.join("starling.db")
    }
    pub fn media_dir(&self) -> PathBuf {
        self.data_dir.join("media")
    }
    pub fn arti_dir(&self) -> PathBuf {
        self.data_dir.join("arti")
    }
    pub fn admin_sock(&self) -> PathBuf {
        self.data_dir.join("admin.sock")
    }
}
