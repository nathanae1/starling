//! Crockford base32, ported byte-for-byte from
//! `services/crypto/crockford_base32.dart`.
//!
//! Alphabet `0123456789abcdefghjkmnpqrstvwxyz` (skips i l o u), lowercase
//! output, no padding. 32 input bytes → exactly 52 characters. Decoding is
//! case-insensitive and normalizes look-alikes (i,l → 1; o → 0; u is not
//! normalized).

const ALPHABET: &[u8; 32] = b"0123456789abcdefghjkmnpqrstvwxyz";

/// Encode bytes as lowercase Crockford base32 (no padding).
pub fn crockford_base32_encode(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return String::new();
    }
    let out_len = (bytes.len() * 8 + 4) / 5;
    let mut out = String::with_capacity(out_len);
    let mut buffer: u32 = 0;
    let mut bits: u32 = 0;
    for &byte in bytes {
        buffer = (buffer << 8) | byte as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            let idx = ((buffer >> bits) & 0x1f) as usize;
            out.push(ALPHABET[idx] as char);
        }
    }
    if bits > 0 {
        let idx = ((buffer << (5 - bits)) & 0x1f) as usize;
        out.push(ALPHABET[idx] as char);
    }
    out
}

/// Decode a Crockford base32 string. Case-insensitive. Returns `None` on
/// any illegal character.
pub fn crockford_base32_decode(encoded: &str) -> Option<Vec<u8>> {
    if encoded.is_empty() {
        return Some(Vec::new());
    }
    let out_len = (encoded.len() * 5) / 8;
    let mut out = Vec::with_capacity(out_len);
    let mut buffer: u32 = 0;
    let mut bits: u32 = 0;
    for c in encoded.bytes() {
        let value = char_value(c)? as u32;
        buffer = (buffer << 5) | value;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xff) as u8);
        }
    }
    Some(out)
}

fn char_value(code_unit: u8) -> Option<u8> {
    let mut c = code_unit;
    // Uppercase → lowercase.
    if (0x41..=0x5a).contains(&c) {
        c += 0x20;
    }
    // Look-alike normalization: i, l → 1; o → 0. (u is not normalized.)
    if c == 0x69 || c == 0x6c {
        c = 0x31;
    }
    if c == 0x6f {
        c = 0x30;
    }
    // Digits 0-9.
    if (0x30..=0x39).contains(&c) {
        return Some(c - 0x30);
    }
    // Letters a-z (minus i, l, o, u — which the alphabet skips).
    if (0x61..=0x7a).contains(&c) {
        if let Some(idx) = ALPHABET.iter().position(|&a| a == c) {
            return Some(idx as u8);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_32_bytes_is_52_chars() {
        let bytes: Vec<u8> = (0..32).collect();
        let enc = crockford_base32_encode(&bytes);
        assert_eq!(enc.len(), 52);
        assert_eq!(crockford_base32_decode(&enc).unwrap(), bytes);
    }

    #[test]
    fn lookalike_normalization() {
        // 'i','l' → '1', 'o' → '0'; decoding is case-insensitive.
        let a = crockford_base32_decode("ILO1").unwrap();
        let b = crockford_base32_decode("1101").unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn rejects_illegal_char() {
        assert!(crockford_base32_decode("uu!!").is_none());
    }
}
