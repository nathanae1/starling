import 'dart:typed_data';

import '../../models/ephemeral_encrypted_event.dart';
import '../../models/signaling_message.dart';
import '../crypto/crockford_base32.dart';
import '../crypto_service.dart';

/// Maximum clock skew (seconds) accepted on an inbound signaling envelope.
/// Mirrors the `/ws/signal` shelf handler's replay window
/// (`signaling_handler.dart`).
const int _replayWindowSeconds = 30;

/// Thrown by [unwrapSignalingMessage] when an envelope fails any check
/// (wrong recipient, decrypt failure, malformed inner message, expired
/// timestamp). The dispatcher catches and drops the offending bytes
/// without tearing down the channel.
class SignalingEnvelopeException implements Exception {
  SignalingEnvelopeException(this.message);
  final String message;
  @override
  String toString() => 'SignalingEnvelopeException: $message';
}

/// Wrap a [SignalingMessage] in an [EphemeralEncryptedEvent] addressed to
/// [recipientPubkey], encrypted under the pairwise signaling key derived
/// via [CryptoService.deriveSignalingKey].
Uint8List wrapSignalingMessage({
  required CryptoService crypto,
  required SignalingMessage message,
  required String myPubkey,
  required Uint8List mySecretKey,
  required String recipientPubkey,
}) {
  final recipientPubkeyBytes = crockfordBase32Decode(recipientPubkey);
  final key = crypto.deriveSignalingKey(
    mySecretKey: mySecretKey,
    theirPubkey: recipientPubkeyBytes,
  );
  final nonce = crypto.randomBytes(24);
  final payload = crypto.encryptEphemeral(
    key: key,
    nonce: nonce,
    plaintext: message.toBytes(),
  );
  final envelope = EphemeralEncryptedEvent(
    senderPubkey: myPubkey,
    recipientPubkey: recipientPubkey,
    nonce: nonce,
    payload: payload,
  );
  return envelope.toBytes();
}

/// Decode + decrypt the inverse of [wrapSignalingMessage]. Throws
/// [SignalingEnvelopeException] on every failure mode so the dispatcher
/// can log + drop without ever propagating an unrecoverable error.
SignalingMessage unwrapSignalingMessage({
  required CryptoService crypto,
  required Uint8List envelopeBytes,
  required String myPubkey,
  required Uint8List mySecretKey,
  DateTime Function()? now,
}) {
  final EphemeralEncryptedEvent envelope;
  try {
    envelope = EphemeralEncryptedEvent.fromBytes(envelopeBytes);
  } catch (e) {
    throw SignalingEnvelopeException('failed to decode envelope: $e');
  }

  if (envelope.recipientPubkey != myPubkey) {
    throw SignalingEnvelopeException(
      'envelope addressed to ${envelope.recipientPubkey}, not $myPubkey',
    );
  }

  final Uint8List senderPubkeyBytes;
  try {
    senderPubkeyBytes = crockfordBase32Decode(envelope.senderPubkey);
  } catch (e) {
    throw SignalingEnvelopeException('invalid sender pubkey encoding: $e');
  }

  final Uint8List plaintext;
  try {
    final key = crypto.deriveSignalingKey(
      mySecretKey: mySecretKey,
      theirPubkey: senderPubkeyBytes,
    );
    plaintext = crypto.decryptEphemeral(
      key: key,
      nonce: envelope.nonce,
      ciphertext: envelope.payload,
    );
  } catch (e) {
    throw SignalingEnvelopeException('decrypt failed: $e');
  }

  final SignalingMessage inner;
  try {
    inner = SignalingMessage.fromBytes(plaintext);
  } catch (e) {
    throw SignalingEnvelopeException('inner message malformed: $e');
  }

  // The inner.timestamp is in seconds (matches signaling_handler's wire
  // contract). Reject anything outside the ±30s window.
  final nowSeconds =
      (now ?? DateTime.now).call().millisecondsSinceEpoch ~/ 1000;
  if ((nowSeconds - inner.timestamp).abs() > _replayWindowSeconds) {
    throw SignalingEnvelopeException(
      'timestamp ${inner.timestamp} outside ±${_replayWindowSeconds}s '
      'window (now=$nowSeconds)',
    );
  }

  return inner;
}
