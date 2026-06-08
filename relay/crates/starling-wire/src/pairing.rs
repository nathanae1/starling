//! Pairing handshake types + the signed-claim derivation.
//!
//! Mirrors `services/relay_pairing_initiator.dart`. The phone signs
//! `blake2b256(claim)` where
//! `claim = "starling-relay-pair-v1" || owner_pubkey(32) || utf8(relay_onion) || token`
//! and `relay_onion` is the **admin** onion the QR advertised. The relay
//! recomputes the same digest and verifies the Ed25519 signature.

use serde::{Deserialize, Serialize};

use crate::sig::blake2b256;

/// Domain-separation tag bound into the pairing claim.
pub const PAIRING_CLAIM_TAG: &[u8] = b"starling-relay-pair-v1";

/// Compute the 32-byte claim digest the Owner signs.
pub fn compute_pair_claim(owner_pubkey: &[u8; 32], relay_onion: &str, token: &[u8]) -> [u8; 32] {
    let mut buf =
        Vec::with_capacity(PAIRING_CLAIM_TAG.len() + 32 + relay_onion.len() + token.len());
    buf.extend_from_slice(PAIRING_CLAIM_TAG);
    buf.extend_from_slice(owner_pubkey);
    buf.extend_from_slice(relay_onion.as_bytes());
    buf.extend_from_slice(token);
    blake2b256(&buf)
}

/// Stable per-pairing id returned to the phone (`relay_id`). The phone
/// persists it as an opaque string; we derive it deterministically so a
/// re-pair against the same per-Owner onion yields the same id.
pub fn relay_id(owner_pubkey: &[u8], relay_onion: &str) -> String {
    let mut buf = Vec::with_capacity(owner_pubkey.len() + relay_onion.len());
    buf.extend_from_slice(owner_pubkey);
    buf.extend_from_slice(relay_onion.as_bytes());
    hex::encode(blake2b256(&buf))
}

/// The CBOR body the phone POSTs to `/pair`:
/// `{owner_pubkey: base64-string, pairing_token: bytes, sig: bytes}`.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PairingClaimWire {
    /// Base64 (standard, padded) of the raw 32-byte Ed25519 pubkey.
    pub owner_pubkey: String,
    #[serde(with = "serde_bytes")]
    pub pairing_token: Vec<u8>,
    #[serde(with = "serde_bytes")]
    pub sig: Vec<u8>,
}

/// The 200 response: `{relay_onion, relay_id}` (both strings).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairResponse {
    pub relay_onion: String,
    pub relay_id: String,
}

/// The CBOR carried inside the `starling-relay://pair?card=…` QR:
/// `{relay_onion: admin_onion, pairing_token: bytes, relay_version}`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayQrCard {
    pub relay_onion: String,
    #[serde(with = "serde_bytes")]
    pub pairing_token: Vec<u8>,
    pub relay_version: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claim_is_deterministic_and_binds_inputs() {
        let pk = [7u8; 32];
        let onion = "exampleadminonionaddress.onion";
        let token = [1u8, 2, 3, 4];
        let a = compute_pair_claim(&pk, onion, &token);
        let b = compute_pair_claim(&pk, onion, &token);
        assert_eq!(a, b);
        // Different onion → different claim (token can't be redirected).
        let c = compute_pair_claim(&pk, "other.onion", &token);
        assert_ne!(a, c);
    }

    #[test]
    fn pairing_claim_cbor_roundtrips() {
        let wire = PairingClaimWire {
            owner_pubkey: "AAAA".to_string(),
            pairing_token: vec![9, 9, 9],
            sig: vec![1; 64],
        };
        let mut buf = Vec::new();
        ciborium::into_writer(&wire, &mut buf).unwrap();
        let back: PairingClaimWire = ciborium::from_reader(&buf[..]).unwrap();
        assert_eq!(back.owner_pubkey, wire.owner_pubkey);
        assert_eq!(back.pairing_token, wire.pairing_token);
        assert_eq!(back.sig, wire.sig);
    }
}
