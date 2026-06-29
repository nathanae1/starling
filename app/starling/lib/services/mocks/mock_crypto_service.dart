import 'dart:convert';
import 'dart:typed_data';

import '../crypto_service.dart';
import '../types.dart';

/// In-memory mock CryptoService for testing without native FFI.
/// Uses deterministic values — no real cryptography.
/// Only implements crypto primitives (narrowed interface).
class MockCryptoService implements CryptoService {
  @override
  Future<KeyPair> generateKeyPair() async => KeyPair(
    publicKey: Uint8List.fromList(List.filled(32, 0x01)),
    secretKey: Uint8List.fromList(List.filled(64, 0x02)),
  );

  @override
  Future<List<String>> deriveRecoveryPhrase(Uint8List seed) async =>
      List.generate(24, (i) => 'word${i + 1}');

  @override
  Future<KeyPair> recoverFromPhrase(List<String> words) async =>
      generateKeyPair();

  @override
  Uint8List ed25519ToX25519PublicKey(Uint8List ed25519Pk) => ed25519Pk;

  @override
  Uint8List ed25519ToX25519SecretKey(Uint8List ed25519Sk) =>
      Uint8List.sublistView(ed25519Sk, 0, 32);

  @override
  Uint8List sign(Uint8List privateKey, Uint8List data) {
    // Deterministic mock: return 64 bytes derived from data.
    final padded = Uint8List(64);
    for (var i = 0; i < data.length && i < 64; i++) {
      padded[i] = data[i];
    }
    return padded;
  }

  @override
  bool verify(Uint8List publicKey, Uint8List data, Uint8List signature) => true;

  @override
  Uint8List randomBytes(int length) => Uint8List(length);

  @override
  Uint8List encrypt(Uint8List plaintext, Uint8List nonce, Uint8List key) =>
      Uint8List.fromList(plaintext);

  @override
  Uint8List decrypt(Uint8List ciphertext, Uint8List nonce, Uint8List key) =>
      Uint8List.fromList(ciphertext);

  @override
  Uint8List encryptMedia(Uint8List blob, Uint8List epochKey) {
    // Prepend 24-byte zero nonce, no encryption.
    final result = Uint8List(24 + blob.length);
    result.setRange(24, result.length, blob);
    return result;
  }

  @override
  Uint8List decryptMedia(Uint8List encryptedBlob, Uint8List epochKey) {
    // Strip 24-byte nonce prefix.
    return Uint8List.sublistView(encryptedBlob, 24);
  }

  @override
  Uint8List deriveSharedKey(
    Uint8List myPrivateKey,
    Uint8List theirPublicKey,
    Uint8List requesterPubkey,
    Uint8List responderPubkey,
    int timestamp,
  ) => Uint8List.fromList(List.filled(32, 0xBB));

  @override
  Uint8List deriveSignalingKey({
    required Uint8List mySecretKey,
    required Uint8List theirPubkey,
  }) => Uint8List.fromList(List.filled(32, 0xAA));

  @override
  Uint8List encryptEphemeral({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
  }) => Uint8List.fromList(plaintext);

  @override
  Uint8List decryptEphemeral({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) => Uint8List.fromList(ciphertext);

  @override
  Uint8List blake2b256(Uint8List data) {
    // Simple deterministic hash for testing: use dart:convert's utf8 + base64
    // to produce 32 bytes. Not cryptographically secure.
    final hash = utf8.encode(base64.encode(data));
    final result = Uint8List(32);
    for (var i = 0; i < 32 && i < hash.length; i++) {
      result[i] = hash[i];
    }
    return result;
  }
}
