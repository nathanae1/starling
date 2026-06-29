import 'dart:typed_data';

import 'package:cbor/simple.dart';

import '../../models/models.dart';
import '../content_key_service.dart';
import '../crypto/crockford_base32.dart';

/// In-memory mock ContentKeyService for testing without native FFI.
/// Uses deterministic values — no real cryptography.
class MockContentKeyService implements ContentKeyService {
  final Uint8List _mockFeedKey = Uint8List.fromList(List.filled(32, 0xAA));

  @override
  Future<Uint8List> generateFeedKey() async =>
      Uint8List.fromList(List.filled(32, 0xAA));

  @override
  Uint8List advanceEpoch(Uint8List currentKey) {
    // Deterministic mock: XOR with 0xFF to produce a different key.
    final next = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      next[i] = currentKey[i] ^ 0xFF;
    }
    return next;
  }

  @override
  EncryptedEvent encryptEvent(
    Event event,
    Uint8List chainRoot,
    int epoch,
    int msgSeq,
  ) {
    // No real encryption: CBOR-encode the event directly as the payload.
    final payload = Uint8List.fromList(cbor.encode(event.toMap()));
    return EncryptedEvent(
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      epoch: epoch,
      msgSeq: msgSeq,
      nonce: Uint8List(24), // zero nonce
      payload: payload,
    );
  }

  @override
  Event decryptEvent(EncryptedEvent encryptedEvent, Uint8List chainRoot) {
    final map = cbor.decode(encryptedEvent.payload) as Map<dynamic, dynamic>;
    return Event.fromMap(map).copyWith(msgSeq: encryptedEvent.msgSeq);
  }

  @override
  Uint8List encryptFeedKey(Uint8List feedKey, Uint8List sharedKey) {
    // Prepend 24-byte zero nonce, no encryption.
    final result = Uint8List(24 + feedKey.length);
    result.setRange(24, result.length, feedKey);
    return result;
  }

  @override
  Uint8List decryptFeedKey(Uint8List encryptedFeedKey, Uint8List sharedKey) {
    return Uint8List.sublistView(encryptedFeedKey, 24);
  }

  @override
  String computeEventId(Event event) {
    // Simple deterministic hash for testing. Emits Crockford base32 so the
    // mock matches the real service's event-id format.
    final idFieldsBytes = Uint8List.fromList(cbor.encode(event.toIdFields()));
    final result = Uint8List(32);
    for (var i = 0; i < idFieldsBytes.length; i++) {
      result[i % 32] ^= idFieldsBytes[i];
    }
    return crockfordBase32Encode(result);
  }

  @override
  EncryptedEvent encryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  }) => signAndEncryptForAudience(event, audience, msgSeq: msgSeq).encrypted;

  @override
  ({Event signed, EncryptedEvent encrypted}) signAndEncryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  }) {
    // Deterministic, non-cryptographic stand-in: compute the id the same way
    // the mock would, attach a sentinel signature (all 0xBB), and return both
    // the "signed" event and an encrypted (really CBOR) payload.
    final id = computeEventId(event);
    final signed = event.copyWith(
      id: id,
      sig: Uint8List.fromList(List.filled(64, 0xBB)),
      msgSeq: msgSeq,
    );
    final encrypted = encryptEvent(signed, _mockFeedKey, 0, msgSeq);
    return (signed: signed, encrypted: encrypted);
  }
}
