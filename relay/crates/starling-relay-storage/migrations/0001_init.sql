-- Starling relay schema (Plan 15, R3). Payloads are client-encrypted, so
-- there is no DB-level encryption (SQLCipher was dropped). Foreign keys are
-- enforced per-connection (PRAGMA foreign_keys=ON) so unpair cascades.

CREATE TABLE IF NOT EXISTS paired_owners (
    pubkey               BLOB PRIMARY KEY NOT NULL,   -- raw 32-byte Ed25519 pubkey
    label                TEXT,
    paired_at            INTEGER NOT NULL,
    relay_onion_address  TEXT NOT NULL,               -- this Owner's relay-generated onion
    local_port           INTEGER NOT NULL UNIQUE,     -- loopback port Arti reverse-proxies to
    storage_cap_bytes    INTEGER                       -- NULL → global default
);

CREATE TABLE IF NOT EXISTS pending_pairings (
    token        BLOB PRIMARY KEY NOT NULL,           -- 32 random bytes
    created_at   INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    consumed_at  INTEGER,                              -- NULL until claimed
    created_by   TEXT NOT NULL,                        -- 'web' | 'cli'
    label        TEXT
);
CREATE INDEX IF NOT EXISTS idx_pending_pairings_expires ON pending_pairings(expires_at);

CREATE TABLE IF NOT EXISTS served_events (
    pubkey      BLOB NOT NULL,
    id          TEXT NOT NULL,                         -- plaintext event id (Crockford b32)
    created_at  INTEGER NOT NULL,
    msg_seq     INTEGER NOT NULL,
    nonce       BLOB NOT NULL,
    payload     BLOB NOT NULL,                         -- raw EncryptedEvent CBOR bytes
    PRIMARY KEY (pubkey, id),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_served_events_owner_time
    ON served_events(pubkey, created_at DESC);

CREATE TABLE IF NOT EXISTS served_media (
    pubkey     BLOB NOT NULL,
    hash       TEXT NOT NULL,                          -- 64-char lowercase hex BLAKE2b-256
    size       INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    path       TEXT NOT NULL,                          -- relative to data_dir/media/
    PRIMARY KEY (pubkey, hash),
    FOREIGN KEY (pubkey) REFERENCES paired_owners(pubkey) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS admin_credentials (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    password_hash TEXT NOT NULL,                       -- argon2id
    updated_at    INTEGER NOT NULL
);
