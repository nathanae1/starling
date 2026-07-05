//! Relay configuration: a TOML file overlaid with `STARLING_RELAY_*` env
//! vars. See `config.example.toml`.

use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub data_dir: PathBuf,
    pub bind_admin: String,
    pub disk_cap_bytes: i64,
    pub per_owner_default_cap_bytes: i64,
    pub log_level: String,
    pub pairing_token_ttl_seconds: i64,
    pub local_port_range: [u16; 2],
    pub voice: VoiceConfig,
}

/// `[voice]` — SFU voice hosting (Plan 20). Off by default: enabling it
/// opens the relay's first clearnet socket (one UDP port for media;
/// signaling stays on the per-Owner onions).
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct VoiceConfig {
    pub enabled: bool,
    /// UDP media port. `0` = OS-assigned each boot — fine for LAN/v6
    /// testing, useless behind a port-forward (a startup warning says so).
    pub udp_port: u16,
    /// Extra ICE host candidates ("ip" or "ip:port") for the
    /// port-forwarded-home-NAT case; interface addresses are auto-detected.
    pub advertised_addrs: Vec<String>,
    /// Per-call participant ceiling. A room slot can lower it, never raise.
    pub max_participants: u16,
    /// Live (non-empty) calls across all owners.
    pub max_concurrent_calls: u32,
}

impl Default for VoiceConfig {
    fn default() -> Self {
        VoiceConfig {
            enabled: false,
            udp_port: 0,
            advertised_addrs: Vec::new(),
            max_participants: 12,
            max_concurrent_calls: 4,
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        // Storage-cap defaults single-source from the serving crate.
        let caps = starling_relay_http::Caps::default();
        Config {
            data_dir: PathBuf::from("/var/lib/starling-relay"),
            bind_admin: "127.0.0.1:8088".to_string(),
            disk_cap_bytes: caps.disk_cap,
            per_owner_default_cap_bytes: caps.per_owner_default,
            log_level: "info".to_string(),
            pairing_token_ttl_seconds: 600,
            local_port_range: [17000, 17999],
            voice: VoiceConfig::default(),
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
        cfg.apply_env()?;
        cfg.validate()?;
        Ok(cfg)
    }

    fn apply_env(&mut self) -> Result<()> {
        if let Ok(v) = std::env::var("STARLING_RELAY_DATA_DIR") {
            self.data_dir = PathBuf::from(v);
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_BIND_ADMIN") {
            self.bind_admin = v;
        }
        if let Ok(v) = std::env::var("STARLING_RELAY_LOG_LEVEL") {
            self.log_level = v;
        }
        // Numeric overrides fail LOUDLY: a typo'd cap silently keeping the
        // default is how an operator ends up with an unenforced quota (L1).
        self.disk_cap_bytes = env_parse("STARLING_RELAY_DISK_CAP_BYTES", self.disk_cap_bytes)?;
        self.per_owner_default_cap_bytes = env_parse(
            "STARLING_RELAY_PER_OWNER_DEFAULT_CAP_BYTES",
            self.per_owner_default_cap_bytes,
        )?;
        self.pairing_token_ttl_seconds = env_parse(
            "STARLING_RELAY_PAIRING_TOKEN_TTL_SECONDS",
            self.pairing_token_ttl_seconds,
        )?;
        if let Ok(v) = std::env::var("STARLING_RELAY_LOCAL_PORT_RANGE") {
            self.local_port_range = parse_port_range(&v).ok_or_else(|| {
                anyhow::anyhow!("STARLING_RELAY_LOCAL_PORT_RANGE must be \"start-end\": got {v:?}")
            })?;
        }
        self.voice.enabled = env_parse("STARLING_RELAY_VOICE_ENABLED", self.voice.enabled)?;
        self.voice.udp_port = env_parse("STARLING_RELAY_VOICE_UDP_PORT", self.voice.udp_port)?;
        self.voice.max_participants = env_parse(
            "STARLING_RELAY_VOICE_MAX_PARTICIPANTS",
            self.voice.max_participants,
        )?;
        self.voice.max_concurrent_calls = env_parse(
            "STARLING_RELAY_VOICE_MAX_CONCURRENT_CALLS",
            self.voice.max_concurrent_calls,
        )?;
        if let Ok(v) = std::env::var("STARLING_RELAY_VOICE_ADVERTISED_ADDRS") {
            self.voice.advertised_addrs = v
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .collect();
        }
        Ok(())
    }

    /// Reject nonsensical values up front rather than silently treating a
    /// negative cap as "unlimited" (`accounting.rs` gates on `cap > 0`).
    fn validate(&self) -> Result<()> {
        if self.disk_cap_bytes < 0 {
            bail!("disk_cap_bytes must be >= 0 (0 = unlimited), got {}", self.disk_cap_bytes);
        }
        if self.per_owner_default_cap_bytes < 0 {
            bail!(
                "per_owner_default_cap_bytes must be >= 0 (0 = unlimited), got {}",
                self.per_owner_default_cap_bytes
            );
        }
        if self.pairing_token_ttl_seconds <= 0 {
            bail!(
                "pairing_token_ttl_seconds must be > 0, got {}",
                self.pairing_token_ttl_seconds
            );
        }
        if self.local_port_range[0] > self.local_port_range[1] {
            bail!(
                "local_port_range start must be <= end, got {:?}",
                self.local_port_range
            );
        }
        // Voice bounds hold even when disabled — a typo'd cap should fail
        // at boot, not on the day the operator flips `enabled`.
        if !(2..=24).contains(&self.voice.max_participants) {
            bail!(
                "voice.max_participants must be in 2..=24, got {}",
                self.voice.max_participants
            );
        }
        if self.voice.max_concurrent_calls < 1 {
            bail!("voice.max_concurrent_calls must be >= 1");
        }
        for addr in &self.voice.advertised_addrs {
            addr.parse::<starling_relay_voice::AdvertisedAddr>().map_err(|_| {
                anyhow::anyhow!(
                    "voice.advertised_addrs entry must be an IP or ip:port, got {addr:?}"
                )
            })?;
        }
        Ok(())
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

/// Parse an integer env var, or return `default` when it is unset. An
/// UNPARSEABLE value is an error, not a silent fallback (L1).
fn env_parse<T>(key: &str, default: T) -> Result<T>
where
    T: std::str::FromStr,
    T::Err: std::fmt::Display,
{
    match std::env::var(key) {
        Ok(v) => v
            .parse()
            .map_err(|e| anyhow::anyhow!("{key}={v:?} is not a valid value: {e}")),
        Err(_) => Ok(default),
    }
}

/// Parse `"17000-17999"` into `[start, end]`. `None` on anything malformed
/// or inverted (the env override is then ignored, like the other fields).
fn parse_port_range(s: &str) -> Option<[u16; 2]> {
    let (start, end) = s.trim().split_once('-')?;
    let start: u16 = start.trim().parse().ok()?;
    let end: u16 = end.trim().parse().ok()?;
    (start <= end).then_some([start, end])
}

#[cfg(test)]
mod tests {
    use super::{env_parse, parse_port_range, Config};

    #[test]
    fn parses_valid_range() {
        assert_eq!(parse_port_range("17000-17999"), Some([17000, 17999]));
        assert_eq!(parse_port_range(" 1- 2 "), Some([1, 2]));
        assert_eq!(parse_port_range("8080-8080"), Some([8080, 8080]));
    }

    #[test]
    fn rejects_malformed_or_inverted() {
        assert_eq!(parse_port_range("17000"), None);
        assert_eq!(parse_port_range("17999-17000"), None);
        assert_eq!(parse_port_range("a-b"), None);
        assert_eq!(parse_port_range("17000-99999"), None);
        assert_eq!(parse_port_range(""), None);
    }

    #[test]
    fn env_parse_errors_on_garbage_but_defaults_when_unset() {
        // Unique key so this can't collide with a parallel test's env.
        let key = "STARLING_RELAY_TEST_ENV_PARSE_XYZ";
        std::env::remove_var(key);
        assert_eq!(env_parse::<i64>(key, 42).unwrap(), 42);
        std::env::set_var(key, "5GB"); // human-readable, NOT an i64
        assert!(env_parse::<i64>(key, 42).is_err());
        std::env::set_var(key, "1000");
        assert_eq!(env_parse::<i64>(key, 42).unwrap(), 1000);
        std::env::remove_var(key);
    }

    #[test]
    fn validate_rejects_bad_values() {
        let mut cfg = Config::default();
        cfg.disk_cap_bytes = -1;
        assert!(cfg.validate().is_err());
        cfg = Config::default();
        cfg.per_owner_default_cap_bytes = -5;
        assert!(cfg.validate().is_err());
        cfg = Config::default();
        cfg.pairing_token_ttl_seconds = 0;
        assert!(cfg.validate().is_err());
        cfg = Config::default();
        cfg.local_port_range = [18000, 17000];
        assert!(cfg.validate().is_err());
        // A clean default validates.
        assert!(Config::default().validate().is_ok());
    }

    #[test]
    fn validate_rejects_bad_voice_values() {
        let mut cfg = Config::default();
        cfg.voice.max_participants = 25;
        assert!(cfg.validate().is_err(), "cap ceiling is 24");
        cfg = Config::default();
        cfg.voice.max_participants = 1;
        assert!(cfg.validate().is_err(), "a 1-person call is not a call");
        cfg = Config::default();
        cfg.voice.max_concurrent_calls = 0;
        assert!(cfg.validate().is_err());
        cfg = Config::default();
        cfg.voice.advertised_addrs = vec!["not-an-ip".into()];
        assert!(cfg.validate().is_err());
        cfg = Config::default();
        cfg.voice.advertised_addrs =
            vec!["203.0.113.7".into(), "203.0.113.7:47000".into(), "2001:db8::1".into()];
        assert!(cfg.validate().is_ok());
    }

    #[test]
    fn voice_toml_parses_and_unknown_voice_key_rejected() {
        let cfg: Config = toml::from_str(
            "[voice]\nenabled = true\nudp_port = 47000\nmax_participants = 16\n",
        )
        .unwrap();
        assert!(cfg.voice.enabled);
        assert_eq!(cfg.voice.udp_port, 47000);
        assert_eq!(cfg.voice.max_participants, 16);
        assert_eq!(cfg.voice.max_concurrent_calls, 4, "unset keys keep defaults");

        let err: Result<Config, _> = toml::from_str("[voice]\nudp_prot = 47000\n");
        assert!(err.is_err(), "deny_unknown_fields covers the [voice] table");
    }
}
