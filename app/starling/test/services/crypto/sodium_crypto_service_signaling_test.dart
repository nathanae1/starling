import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('deriveSignalingKey', () {
    test('both sides arrive at the same 32-byte key', () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();

      final aKey = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: b.publicKey,
      );
      final bKey = crypto.deriveSignalingKey(
        mySecretKey: b.secretKey,
        theirPubkey: a.publicKey,
      );

      expect(aKey.length, 32);
      expect(bKey, equals(aKey));
    });

    test('different counterparty → different key', () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();
      final c = await crypto.generateKeyPair();

      final ab = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: b.publicKey,
      );
      final ac = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: c.publicKey,
      );

      expect(ab, isNot(equals(ac)));
    });
  });

  group('encryptEphemeral / decryptEphemeral', () {
    test('round-trip with pairwise signaling key', () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();
      final key = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: b.publicKey,
      );
      final nonce = crypto.randomBytes(24);
      final plaintext = Uint8List.fromList('hello voice room'.codeUnits);

      final ct = crypto.encryptEphemeral(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
      );

      // The recipient derives the same key from the other direction.
      final recipientKey = crypto.deriveSignalingKey(
        mySecretKey: b.secretKey,
        theirPubkey: a.publicKey,
      );
      final pt = crypto.decryptEphemeral(
        key: recipientKey,
        nonce: nonce,
        ciphertext: ct,
      );

      expect(pt, equals(plaintext));
    });

    test('wrong recipient sk fails to decrypt', () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();
      final c = await crypto.generateKeyPair();

      final key = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: b.publicKey,
      );
      final nonce = crypto.randomBytes(24);
      final ct = crypto.encryptEphemeral(
        key: key,
        nonce: nonce,
        plaintext: Uint8List.fromList('private message'.codeUnits),
      );

      // c (wrong recipient) derives a different key vs. a→b.
      final wrongKey = crypto.deriveSignalingKey(
        mySecretKey: c.secretKey,
        theirPubkey: a.publicKey,
      );

      expect(
        () => crypto.decryptEphemeral(
          key: wrongKey,
          nonce: nonce,
          ciphertext: ct,
        ),
        throwsA(anything),
      );
    });

    test('tampered ciphertext fails authentication', () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();
      final key = crypto.deriveSignalingKey(
        mySecretKey: a.secretKey,
        theirPubkey: b.publicKey,
      );
      final nonce = crypto.randomBytes(24);
      final ct = crypto.encryptEphemeral(
        key: key,
        nonce: nonce,
        plaintext: Uint8List.fromList('tamper target'.codeUnits),
      );
      final tampered = Uint8List.fromList(ct)..[0] ^= 0x01;

      expect(
        () => crypto.decryptEphemeral(
          key: key,
          nonce: nonce,
          ciphertext: tampered,
        ),
        throwsA(anything),
      );
    });
  });
}
