import 'dart:typed_data';

import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('ratchetFeedKey', () {
    test('produces 32 bytes', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      expect(ratchetFeedKey(key, crypto).length, 32);
    });

    test('is deterministic', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      expect(ratchetFeedKey(key, crypto), ratchetFeedKey(key, crypto));
    });

    test('produces a different key than the input', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      expect(ratchetFeedKey(key, crypto), isNot(key));
    });

    test('successive ratchets diverge', () {
      final k0 = Uint8List.fromList(List.filled(32, 0x42));
      final k1 = ratchetFeedKey(k0, crypto);
      final k2 = ratchetFeedKey(k1, crypto);
      expect(k0, isNot(k1));
      expect(k1, isNot(k2));
      expect(k0, isNot(k2));
    });

    test('zero input produces non-zero output', () {
      final next = ratchetFeedKey(Uint8List(32), crypto);
      expect(next.any((b) => b != 0), isTrue);
    });

    test('backward derivation is infeasible (smoke check)', () {
      // We cannot actually prove preimage-resistance here, but we can verify
      // that the next key is not trivially related to the input.
      final k = Uint8List.fromList(List.generate(32, (i) => i * 7));
      final next = ratchetFeedKey(k, crypto);
      // No linear relationship like XOR-identity or simple rotation.
      expect(next, isNot(k));
      for (var shift = 1; shift < 32; shift++) {
        final rotated = Uint8List(32);
        for (var i = 0; i < 32; i++) {
          rotated[i] = k[(i + shift) % 32];
        }
        expect(next, isNot(rotated));
      }
    });
  });

  group('deriveEpochKey', () {
    test('delta 0 returns base key unchanged', () {
      final base = Uint8List.fromList(List.generate(32, (i) => i * 3));
      expect(deriveEpochKey(base, 0, crypto), base);
    });

    test('delta 1 matches a single ratchet', () {
      final base = Uint8List.fromList(List.generate(32, (i) => i * 3));
      expect(deriveEpochKey(base, 1, crypto), ratchetFeedKey(base, crypto));
    });

    test('delta N equals N manual applications', () {
      final base = Uint8List.fromList(List.generate(32, (i) => i));
      var manual = base;
      for (var i = 0; i < 5; i++) {
        manual = ratchetFeedKey(manual, crypto);
      }
      expect(deriveEpochKey(base, 5, crypto), manual);
    });

    test('negative delta throws', () {
      expect(
        () => deriveEpochKey(Uint8List(32), -1, crypto),
        throwsArgumentError,
      );
    });
  });

  group('deriveMsgKey', () {
    test('produces 32 bytes', () {
      final root = Uint8List.fromList(List.generate(32, (i) => i));
      expect(deriveMsgKey(root, 0, crypto).length, 32);
    });

    test('is deterministic for the same (root, seq)', () {
      final root = Uint8List.fromList(List.filled(32, 0x42));
      expect(deriveMsgKey(root, 7, crypto), deriveMsgKey(root, 7, crypto));
    });

    test('different seq under same root produces different keys', () {
      final root = Uint8List.fromList(List.filled(32, 0x42));
      expect(
        deriveMsgKey(root, 0, crypto),
        isNot(deriveMsgKey(root, 1, crypto)),
      );
    });

    test('different roots under same seq produce different keys', () {
      final r0 = Uint8List.fromList(List.filled(32, 0x42));
      final r1 = Uint8List.fromList(List.filled(32, 0x43));
      expect(deriveMsgKey(r0, 0, crypto), isNot(deriveMsgKey(r1, 0, crypto)));
    });

    test('msg_key is distinct from chainRoot', () {
      // Domain separation: deriveMsgKey must not produce the chain root,
      // even at seq=0.
      final root = Uint8List.fromList(List.generate(32, (i) => i * 5));
      expect(deriveMsgKey(root, 0, crypto), isNot(root));
    });

    test('msg_key is distinct from ratchetFeedKey output', () {
      // Domain separation: msg_key derivation uses a different domain
      // string than the epoch ratchet.
      final root = Uint8List.fromList(List.generate(32, (i) => i * 5));
      expect(
        deriveMsgKey(root, 0, crypto),
        isNot(ratchetFeedKey(root, crypto)),
      );
    });

    test('negative seq throws', () {
      expect(
        () => deriveMsgKey(Uint8List(32), -1, crypto),
        throwsArgumentError,
      );
    });
  });
}
