import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:collection/collection.dart';

/// An encrypted envelope for ephemeral signaling messages.
///
/// Unlike [EncryptedEvent] which uses the broadcast feed key, ephemeral
/// events are encrypted per-recipient using the pairwise signaling key from
/// `CryptoService.deriveSignalingKey` (X25519 DH + crypto_kdf, 8-byte ctx
/// `'starsig0'`, with the two Ed25519 pubkeys lexicographically sorted into
/// the KDF info so both peers derive the same key). They are delivered via
/// WebSocket, never stored in the events table, and never included in sync
/// responses.
class EphemeralEncryptedEvent {
  const EphemeralEncryptedEvent({
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.nonce,
    required this.payload,
  });

  /// Sender's Ed25519 public key (plaintext, for routing/decryption).
  final String senderPubkey;

  /// Intended recipient's Ed25519 public key.
  final String recipientPubkey;

  /// Random 24-byte nonce (unique per message).
  final Uint8List nonce;

  /// XChaCha20-Poly1305(pairwise_key, nonce, cbor(SignalingMessage)).
  final Uint8List payload;

  Map<String, dynamic> toMap() => {
        'sender_pubkey': senderPubkey,
        'recipient_pubkey': recipientPubkey,
        'nonce': nonce,
        'payload': payload,
      };

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static EphemeralEncryptedEvent fromMap(Map<dynamic, dynamic> map) =>
      EphemeralEncryptedEvent(
        senderPubkey: map['sender_pubkey'] as String,
        recipientPubkey: map['recipient_pubkey'] as String,
        nonce: _toUint8List(map['nonce']),
        payload: _toUint8List(map['payload']),
      );

  static EphemeralEncryptedEvent fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EphemeralEncryptedEvent &&
          senderPubkey == other.senderPubkey &&
          recipientPubkey == other.recipientPubkey &&
          const ListEquality<int>().equals(nonce, other.nonce) &&
          const ListEquality<int>().equals(payload, other.payload);

  @override
  int get hashCode => Object.hash(senderPubkey, recipientPubkey);

  @override
  String toString() =>
      'EphemeralEncryptedEvent(sender: $senderPubkey, '
      'recipient: $recipientPubkey, payloadSize: ${payload.length})';
}

Uint8List _toUint8List(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List) return Uint8List.fromList(value.cast<int>());
  throw ArgumentError('Expected bytes, got ${value.runtimeType}');
}
