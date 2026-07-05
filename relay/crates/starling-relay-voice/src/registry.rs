//! Blinded slot registry: `(owner_pubkey, token_hash)` → per-slot config.
//!
//! The relay stores only `BLAKE2b-256(voiceToken)`; a join presents the
//! preimage. Replace-the-set semantics mirror the DB DAO
//! (`starling-relay-storage::voice_slots`): the phone always pushes the
//! owner's complete slot set.

use std::collections::HashMap;

use starling_wire::voice::VoiceSlotEntry;

#[derive(Debug, Clone, Copy)]
pub(crate) struct SlotInfo {
    pub max_participants: Option<u16>,
}

#[derive(Default)]
pub(crate) struct SlotRegistry {
    slots: HashMap<([u8; 32], [u8; 32]), SlotInfo>,
}

impl SlotRegistry {
    pub fn replace_set(&mut self, owner: [u8; 32], entries: &[VoiceSlotEntry]) {
        self.slots.retain(|(o, _), _| *o != owner);
        for e in entries {
            let Ok(hash) = <[u8; 32]>::try_from(e.token_hash.as_slice()) else {
                continue; // non-32-byte hashes are rejected upstream; belt and braces
            };
            self.slots.insert((owner, hash), SlotInfo { max_participants: e.max_participants });
        }
    }

    pub fn drop_owner(&mut self, owner: &[u8; 32]) {
        self.slots.retain(|(o, _), _| o != owner);
    }

    pub fn lookup(&self, owner: &[u8; 32], token_hash: &[u8; 32]) -> Option<SlotInfo> {
        self.slots.get(&(*owner, *token_hash)).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(byte: u8, cap: Option<u16>) -> VoiceSlotEntry {
        VoiceSlotEntry { token_hash: vec![byte; 32], max_participants: cap }
    }

    #[test]
    fn replace_set_replaces_only_that_owner() {
        let mut reg = SlotRegistry::default();
        reg.replace_set([1; 32], &[entry(0xaa, Some(8)), entry(0xbb, None)]);
        reg.replace_set([2; 32], &[entry(0xcc, None)]);

        reg.replace_set([1; 32], &[entry(0xdd, None)]);
        assert!(reg.lookup(&[1; 32], &[0xaa; 32]).is_none(), "old slot gone");
        assert!(reg.lookup(&[1; 32], &[0xdd; 32]).is_some(), "new slot present");
        assert!(reg.lookup(&[2; 32], &[0xcc; 32]).is_some(), "other owner untouched");
    }

    #[test]
    fn drop_owner_removes_all_slots() {
        let mut reg = SlotRegistry::default();
        reg.replace_set([1; 32], &[entry(0xaa, None), entry(0xbb, None)]);
        reg.drop_owner(&[1; 32]);
        assert!(reg.lookup(&[1; 32], &[0xaa; 32]).is_none());
        assert!(reg.lookup(&[1; 32], &[0xbb; 32]).is_none());
    }

    #[test]
    fn lookup_is_owner_scoped() {
        let mut reg = SlotRegistry::default();
        reg.replace_set([1; 32], &[entry(0xaa, None)]);
        assert!(reg.lookup(&[2; 32], &[0xaa; 32]).is_none());
    }
}
