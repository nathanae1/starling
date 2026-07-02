import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/ephemeral_encrypted_event.dart';
import 'package:starling/models/signaling_message.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/signaling/signaling_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  SignalingMessage makeMessage({
    required String senderPubkey,
    int? timestamp,
  }) => SignalingMessage(
    type: SignalingMessageType.libp2pConnect,
    roomId: '',
    senderPubkey: senderPubkey,
    payload: const {'peer_id': 'QmTestPeerId', 'punch_at_unix_ms': 0},
    timestamp: timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
  );

  test('wrap → unwrap round-trip recovers the inner message', () async {
    final sender = await crypto.generateKeyPair();
    final recipient = await crypto.generateKeyPair();
    final senderEnc = crockfordBase32Encode(sender.publicKey);
    final recipientEnc = crockfordBase32Encode(recipient.publicKey);

    final message = makeMessage(senderPubkey: senderEnc);

    final envelopeBytes = wrapSignalingMessage(
      crypto: crypto,
      message: message,
      myPubkey: senderEnc,
      mySecretKey: sender.secretKey,
      recipientPubkey: recipientEnc,
    );

    final decoded = unwrapSignalingMessage(
      crypto: crypto,
      envelopeBytes: envelopeBytes,
      myPubkey: recipientEnc,
      mySecretKey: recipient.secretKey,
    );

    expect(decoded.type, SignalingMessageType.libp2pConnect);
    expect(decoded.senderPubkey, senderEnc);
    expect(decoded.payload['peer_id'], 'QmTestPeerId');
    expect(decoded.timestamp, message.timestamp);
  });

  test('tampered payload byte → SignalingEnvelopeException', () async {
    final sender = await crypto.generateKeyPair();
    final recipient = await crypto.generateKeyPair();
    final senderEnc = crockfordBase32Encode(sender.publicKey);
    final recipientEnc = crockfordBase32Encode(recipient.publicKey);

    final envelopeBytes = wrapSignalingMessage(
      crypto: crypto,
      message: makeMessage(senderPubkey: senderEnc),
      myPubkey: senderEnc,
      mySecretKey: sender.secretKey,
      recipientPubkey: recipientEnc,
    );

    // Decode → flip a payload byte → re-encode.
    final tamperedEnvelope = EphemeralEncryptedEvent.fromBytes(envelopeBytes);
    final tamperedPayload = Uint8List.fromList(tamperedEnvelope.payload)
      ..[0] ^= 0x01;
    final reEncoded = EphemeralEncryptedEvent(
      senderPubkey: tamperedEnvelope.senderPubkey,
      recipientPubkey: tamperedEnvelope.recipientPubkey,
      nonce: tamperedEnvelope.nonce,
      payload: tamperedPayload,
    ).toBytes();

    expect(
      () => unwrapSignalingMessage(
        crypto: crypto,
        envelopeBytes: reEncoded,
        myPubkey: recipientEnc,
        mySecretKey: recipient.secretKey,
      ),
      throwsA(isA<SignalingEnvelopeException>()),
    );
  });

  test('wrong recipient pubkey on envelope → throws', () async {
    final sender = await crypto.generateKeyPair();
    final recipient = await crypto.generateKeyPair();
    final intruder = await crypto.generateKeyPair();
    final senderEnc = crockfordBase32Encode(sender.publicKey);
    final recipientEnc = crockfordBase32Encode(recipient.publicKey);
    final intruderEnc = crockfordBase32Encode(intruder.publicKey);

    final envelopeBytes = wrapSignalingMessage(
      crypto: crypto,
      message: makeMessage(senderPubkey: senderEnc),
      myPubkey: senderEnc,
      mySecretKey: sender.secretKey,
      recipientPubkey: recipientEnc,
    );

    // Intruder reads with their key — envelope's recipientPubkey is for
    // the real recipient, not the intruder.
    expect(
      () => unwrapSignalingMessage(
        crypto: crypto,
        envelopeBytes: envelopeBytes,
        myPubkey: intruderEnc,
        mySecretKey: intruder.secretKey,
      ),
      throwsA(isA<SignalingEnvelopeException>()),
    );
  });

  test('expired timestamp (outside ±30s window) → throws', () async {
    final sender = await crypto.generateKeyPair();
    final recipient = await crypto.generateKeyPair();
    final senderEnc = crockfordBase32Encode(sender.publicKey);
    final recipientEnc = crockfordBase32Encode(recipient.publicKey);

    final expired = makeMessage(
      senderPubkey: senderEnc,
      timestamp: (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 120,
    );

    final envelopeBytes = wrapSignalingMessage(
      crypto: crypto,
      message: expired,
      myPubkey: senderEnc,
      mySecretKey: sender.secretKey,
      recipientPubkey: recipientEnc,
    );

    expect(
      () => unwrapSignalingMessage(
        crypto: crypto,
        envelopeBytes: envelopeBytes,
        myPubkey: recipientEnc,
        mySecretKey: recipient.secretKey,
      ),
      throwsA(isA<SignalingEnvelopeException>()),
    );
  });

  test('malformed envelope bytes → throws', () {
    final junk = Uint8List.fromList([0xff, 0x00, 0xff, 0x00]);
    expect(
      () => unwrapSignalingMessage(
        crypto: crypto,
        envelopeBytes: junk,
        myPubkey: 'whatever',
        mySecretKey: Uint8List(64),
      ),
      throwsA(isA<SignalingEnvelopeException>()),
    );
  });
}
