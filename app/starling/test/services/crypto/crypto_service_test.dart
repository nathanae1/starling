import 'dart:typed_data';

import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('keys', () {
    test('generateKeyPair returns 32-byte pubkey and 64-byte secret', () async {
      final kp = await crypto.generateKeyPair();
      expect(kp.publicKey.length, 32);
      expect(kp.secretKey.length, 64);
    });

    test(
      'ed25519 → x25519 conversion returns 32 bytes for pk and sk',
      () async {
        final kp = await crypto.generateKeyPair();
        final xpk = crypto.ed25519ToX25519PublicKey(kp.publicKey);
        final xsk = crypto.ed25519ToX25519SecretKey(kp.secretKey);
        expect(xpk.length, 32);
        expect(xsk.length, 32);
      },
    );
  });

  group('sign/verify', () {
    test('sign + verify round trip', () async {
      final kp = await crypto.generateKeyPair();
      final data = Uint8List.fromList('hello starling'.codeUnits);
      final sig = crypto.sign(kp.secretKey, data);
      expect(sig.length, 64);
      expect(crypto.verify(kp.publicKey, data, sig), isTrue);
    });

    test('tampered data fails verify', () async {
      final kp = await crypto.generateKeyPair();
      final data = Uint8List.fromList('hello starling'.codeUnits);
      final sig = crypto.sign(kp.secretKey, data);
      final tampered = Uint8List.fromList(data)..[0] ^= 0x01;
      expect(crypto.verify(kp.publicKey, tampered, sig), isFalse);
    });

    test('wrong key fails verify', () async {
      final kp1 = await crypto.generateKeyPair();
      final kp2 = await crypto.generateKeyPair();
      final data = Uint8List.fromList('hello starling'.codeUnits);
      final sig = crypto.sign(kp1.secretKey, data);
      expect(crypto.verify(kp2.publicKey, data, sig), isFalse);
    });
  });

  group('encrypt/decrypt', () {
    test('explicit-nonce encrypt/decrypt round trip', () {
      final key = crypto.randomBytes(32);
      final nonce = crypto.randomBytes(24);
      final plaintext = Uint8List.fromList('this is a test'.codeUnits);
      final ct = crypto.encrypt(plaintext, nonce, key);
      expect(ct, isNot(plaintext));
      expect(crypto.decrypt(ct, nonce, key), plaintext);
    });

    test('wrong key throws on decrypt', () {
      final key1 = crypto.randomBytes(32);
      final key2 = crypto.randomBytes(32);
      final nonce = crypto.randomBytes(24);
      final ct = crypto.encrypt(
        Uint8List.fromList('secret'.codeUnits),
        nonce,
        key1,
      );
      expect(() => crypto.decrypt(ct, nonce, key2), throwsA(anything));
    });

    test('random nonces produce different ciphertexts for same plaintext', () {
      final key = crypto.randomBytes(32);
      final plaintext = Uint8List.fromList('repeat'.codeUnits);
      final ct1 = crypto.encrypt(plaintext, crypto.randomBytes(24), key);
      final ct2 = crypto.encrypt(plaintext, crypto.randomBytes(24), key);
      expect(ct1, isNot(ct2));
    });

    test('encryptMedia/decryptMedia round trip with prepended nonce', () {
      final key = crypto.randomBytes(32);
      final blob = Uint8List.fromList(List.generate(1000, (i) => i & 0xff));
      final enc = crypto.encryptMedia(blob, key);
      expect(enc.length, blob.length + 24 + 16); // nonce + poly1305 tag
      expect(crypto.decryptMedia(enc, key), blob);
    });

    test('decryptMedia throws on wrong key', () {
      final key1 = crypto.randomBytes(32);
      final key2 = crypto.randomBytes(32);
      final enc = crypto.encryptMedia(
        Uint8List.fromList('photo'.codeUnits),
        key1,
      );
      expect(() => crypto.decryptMedia(enc, key2), throwsA(anything));
    });
  });

  group('random bytes', () {
    test('randomBytes returns requested length', () {
      expect(crypto.randomBytes(16).length, 16);
      expect(crypto.randomBytes(24).length, 24);
      expect(crypto.randomBytes(32).length, 32);
    });

    test('successive calls return different bytes (probabilistic)', () {
      final a = crypto.randomBytes(32);
      final b = crypto.randomBytes(32);
      expect(a, isNot(b));
    });
  });

  group('blake2b256', () {
    test('produces 32 bytes', () {
      expect(crypto.blake2b256(Uint8List.fromList('x'.codeUnits)).length, 32);
    });

    test('is deterministic', () {
      final input = Uint8List.fromList('starling'.codeUnits);
      expect(crypto.blake2b256(input), crypto.blake2b256(input));
    });

    test('different inputs produce different outputs', () {
      final a = crypto.blake2b256(Uint8List.fromList('a'.codeUnits));
      final b = crypto.blake2b256(Uint8List.fromList('b'.codeUnits));
      expect(a, isNot(b));
    });

    test('empty input produces 32 bytes', () {
      expect(crypto.blake2b256(Uint8List(0)).length, 32);
    });
  });

  group('recovery phrase', () {
    test('generateKeyPair → deriveRecoveryPhrase → recoverFromPhrase '
        'recovers the same keys', () async {
      // Start from a known 32-byte seed so we can verify recoverability.
      final seed = crypto.randomBytes(32);
      final words = await crypto.deriveRecoveryPhrase(seed);
      expect(words.length, 24);

      final recovered = await crypto.recoverFromPhrase(words);
      expect(recovered.publicKey.length, 32);
      expect(recovered.secretKey.length, 64);

      // The recovered secret key's embedded seed should match the original.
      // In libsodium's Ed25519 expanded secret key, bytes 0..31 are the seed.
      expect(recovered.secretKey.sublist(0, 32), seed);
    });

    test('tampered phrase fails checksum', () async {
      final seed = crypto.randomBytes(32);
      final words = await crypto.deriveRecoveryPhrase(seed);
      // Swap two words that are likely to break the checksum.
      final tampered = [...words];
      if (tampered[0] != tampered[1]) {
        final tmp = tampered[0];
        tampered[0] = tampered[1];
        tampered[1] = tmp;
      } else {
        // Extremely unlikely; pick another pair.
        tampered[0] = words.firstWhere((w) => w != words[0]);
      }
      expect(() => crypto.recoverFromPhrase(tampered), throwsArgumentError);
    });
  });

  group('key exchange', () {
    test('Alice and Bob derive the same shared key', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      const timestamp = 1_712_000_000;

      final aliceXsk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXsk = crypto.ed25519ToX25519SecretKey(bob.secretKey);
      final aliceXpk = crypto.ed25519ToX25519PublicKey(alice.publicKey);
      final bobXpk = crypto.ed25519ToX25519PublicKey(bob.publicKey);

      // Same requester/responder labels on both sides → same derived key.
      final aliceShared = crypto.deriveSharedKey(
        aliceXsk,
        bobXpk,
        alice.publicKey,
        bob.publicKey,
        timestamp,
      );
      final bobShared = crypto.deriveSharedKey(
        bobXsk,
        aliceXpk,
        alice.publicKey,
        bob.publicKey,
        timestamp,
      );

      expect(aliceShared.length, 32);
      expect(aliceShared, bobShared);
    });

    test('different timestamps produce different shared keys', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();

      final aliceXsk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXpk = crypto.ed25519ToX25519PublicKey(bob.publicKey);

      final t1 = crypto.deriveSharedKey(
        aliceXsk,
        bobXpk,
        alice.publicKey,
        bob.publicKey,
        1_712_000_000,
      );
      final t2 = crypto.deriveSharedKey(
        aliceXsk,
        bobXpk,
        alice.publicKey,
        bob.publicKey,
        1_712_000_001,
      );
      expect(t1, isNot(t2));
    });

    test(
      'swapped requester/responder produce different keys (anti-reflection)',
      () async {
        final alice = await crypto.generateKeyPair();
        final bob = await crypto.generateKeyPair();
        const timestamp = 1_712_000_000;

        final aliceXsk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
        final bobXpk = crypto.ed25519ToX25519PublicKey(bob.publicKey);

        final a = crypto.deriveSharedKey(
          aliceXsk,
          bobXpk,
          alice.publicKey,
          bob.publicKey,
          timestamp,
        );
        final b = crypto.deriveSharedKey(
          aliceXsk,
          bobXpk,
          bob.publicKey, // swapped
          alice.publicKey,
          timestamp,
        );
        expect(a, isNot(b));
      },
    );

    test('Alice encrypts feed key, Bob decrypts', () async {
      final alice = await crypto.generateKeyPair();
      final bob = await crypto.generateKeyPair();
      const timestamp = 1_712_000_000;

      final aliceXsk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXsk = crypto.ed25519ToX25519SecretKey(bob.secretKey);
      final aliceXpk = crypto.ed25519ToX25519PublicKey(alice.publicKey);
      final bobXpk = crypto.ed25519ToX25519PublicKey(bob.publicKey);

      final aliceShared = crypto.deriveSharedKey(
        aliceXsk,
        bobXpk,
        alice.publicKey,
        bob.publicKey,
        timestamp,
      );
      final bobShared = crypto.deriveSharedKey(
        bobXsk,
        aliceXpk,
        alice.publicKey,
        bob.publicKey,
        timestamp,
      );

      final feedKey = crypto.randomBytes(32);
      final nonce = crypto.randomBytes(24);
      final wrapped = crypto.encrypt(feedKey, nonce, aliceShared);
      final unwrapped = crypto.decrypt(wrapped, nonce, bobShared);
      expect(unwrapped, feedKey);
    });
  });
}
