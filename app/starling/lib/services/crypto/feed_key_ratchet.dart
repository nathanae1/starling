import 'dart:typed_data';

import '../crypto_service.dart';

/// MegOLM-style hash ratchet suffix. Keeps the ratchet output distinct from
/// any other BLAKE2b-256 hash we compute elsewhere.
const _ratchetSuffix = 'starling-ratchet-v1';

/// Domain string for per-message key derivation. Distinct from
/// [_ratchetSuffix] so a chain root can never be confused with a
/// per-message key, even though both are BLAKE2b-256 outputs over the
/// same input length.
const _msgKeySuffix = 'starling-msg-key-v1';

/// Advance a feed key to the next epoch.
///
/// `nextKey = BLAKE2b-256(currentKey || "starling-ratchet-v1")`
///
/// This is one-way: knowing `epoch_n` lets you derive `epoch_{n+1}`, but the
/// hash is preimage-resistant so you cannot derive `epoch_{n-1}`.
Uint8List ratchetFeedKey(Uint8List currentKey, CryptoService crypto) {
  final suffix = Uint8List.fromList(_ratchetSuffix.codeUnits);
  final input = Uint8List(currentKey.length + suffix.length);
  input.setRange(0, currentKey.length, currentKey);
  input.setRange(currentKey.length, input.length, suffix);
  return crypto.blake2b256(input);
}

/// Apply the ratchet [delta] times to derive a future epoch key.
///
/// `delta == 0` returns [baseKey] unchanged. Negative deltas are rejected —
/// the ratchet is one-way.
Uint8List deriveEpochKey(Uint8List baseKey, int delta, CryptoService crypto) {
  if (delta < 0) {
    throw ArgumentError('delta must be non-negative (ratchet is one-way)');
  }
  var key = baseKey;
  for (var i = 0; i < delta; i++) {
    key = ratchetFeedKey(key, crypto);
  }
  return key;
}

/// Per-message key derivation (MegOLM-shaped, flat — i.e. without
/// internal ratcheting). Each message published in epoch `e` is encrypted
/// under
/// `msg_key_n = BLAKE2b-256(chainRoot_e || "starling-msg-key-v1" || u64_be(n))`.
///
/// Properties:
/// - Domain separation prevents collisions with [ratchetFeedKey] output.
/// - `msgSeq` is encoded as 8 bytes big-endian, platform-independent.
/// - Flat (not ratcheting): knowing `chainRoot_e` reveals every
///   `msg_key_n` for that epoch. A future plan can replace this with a
///   ratcheting derivation for forward secrecy *within* an epoch — the
///   change is local to this function plus sender-side state.
Uint8List deriveMsgKey(Uint8List chainRoot, int msgSeq, CryptoService crypto) {
  if (msgSeq < 0) {
    throw ArgumentError('msgSeq must be non-negative');
  }
  final suffix = Uint8List.fromList(_msgKeySuffix.codeUnits);
  final input = Uint8List(chainRoot.length + suffix.length + 8);
  input.setRange(0, chainRoot.length, chainRoot);
  input.setRange(chainRoot.length, chainRoot.length + suffix.length, suffix);
  // Big-endian u64. Using ByteData rather than bit-shifts to avoid the
  // JS-number-precision footgun on Dart-for-web (we don't ship to web,
  // but the helper is simple and explicit).
  final bd = ByteData.view(input.buffer, chainRoot.length + suffix.length, 8);
  bd.setUint64(0, msgSeq, Endian.big);
  return crypto.blake2b256(input);
}
