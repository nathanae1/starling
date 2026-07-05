-- Voice (SFU) slot registry (Plan 20). Rooms are registered as blinded
-- token hashes: `token_hash = BLAKE2b-256(voiceToken)`. The relay never
-- sees the preimage until a participant joins, and never learns which room
-- a slot belongs to. Unpair removes the rows via the owner cascade.
CREATE TABLE IF NOT EXISTS voice_slots (
    pubkey BLOB NOT NULL REFERENCES paired_owners(pubkey) ON DELETE CASCADE,
    token_hash BLOB NOT NULL,
    max_participants INTEGER,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (pubkey, token_hash)
);
