import 'dart:math';
import 'dart:typed_data';

import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crockfordBase32', () {
    test('empty input produces empty output', () {
      expect(crockfordBase32Encode(Uint8List(0)), '');
      expect(crockfordBase32Decode(''), Uint8List(0));
    });

    test('32-byte input encodes to exactly 52 chars', () {
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = i;
      }
      final encoded = crockfordBase32Encode(bytes);
      expect(encoded.length, 52);
    });

    test('round-trip: 32 bytes of zeros', () {
      final bytes = Uint8List(32);
      final encoded = crockfordBase32Encode(bytes);
      expect(encoded, '0' * 52);
      final decoded = crockfordBase32Decode(encoded);
      expect(decoded, bytes);
    });

    test('round-trip: 32 bytes of 0xff', () {
      final bytes = Uint8List.fromList(List.filled(32, 0xff));
      final encoded = crockfordBase32Encode(bytes);
      final decoded = crockfordBase32Decode(encoded);
      expect(decoded, bytes);
    });

    test('round-trip: 1000 random 32-byte inputs', () {
      final random = Random(0x5eed);
      for (var trial = 0; trial < 1000; trial++) {
        final bytes = Uint8List.fromList(
          List.generate(32, (_) => random.nextInt(256)),
        );
        final encoded = crockfordBase32Encode(bytes);
        expect(encoded.length, 52, reason: 'trial $trial');
        final decoded = crockfordBase32Decode(encoded);
        expect(decoded, bytes, reason: 'trial $trial');
      }
    });

    test('round-trip: various lengths', () {
      for (final len in [1, 2, 3, 5, 8, 16, 20, 64]) {
        final bytes = Uint8List.fromList(
          List.generate(len, (i) => (i * 17 + 3) & 0xff),
        );
        final encoded = crockfordBase32Encode(bytes);
        final decoded = crockfordBase32Decode(encoded);
        expect(decoded, bytes, reason: 'length $len');
      }
    });

    test('encoded output is lowercase', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => i * 7));
      final encoded = crockfordBase32Encode(bytes);
      expect(encoded, encoded.toLowerCase());
    });

    test('decode is case-insensitive', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => i));
      final encoded = crockfordBase32Encode(bytes);
      final upperDecoded = crockfordBase32Decode(encoded.toUpperCase());
      expect(upperDecoded, bytes);
    });

    test('decode normalizes I/L → 1 and O → 0', () {
      final bytes = Uint8List.fromList([0x08, 0x40]); // 0000 1000 0100 0000
      final encoded = crockfordBase32Encode(bytes);
      // Whatever the canonical form, check that I/L/O variants round-trip.
      final withILookalike = encoded.replaceAll('1', 'I').replaceAll('0', 'O');
      final decoded1 = crockfordBase32Decode(withILookalike);
      expect(decoded1, bytes);
      final withLLookalike = encoded.replaceAll('1', 'l');
      final decoded2 = crockfordBase32Decode(withLLookalike);
      expect(decoded2, bytes);
    });

    test('decode throws on illegal character', () {
      expect(() => crockfordBase32Decode('u'), throwsFormatException);
      expect(() => crockfordBase32Decode('!'), throwsFormatException);
    });

    test('known-answer: all zeros', () {
      expect(crockfordBase32Encode(Uint8List(5)), '00000000');
    });

    test('known-answer: [0xff]', () {
      // 0xff = 11111111. First 5 bits = 11111 = 31 = 'z'. Remaining 3 bits = 111
      // → left-shift by 2 → 11100 = 28 → 'w'.
      final encoded = crockfordBase32Encode(Uint8List.fromList([0xff]));
      expect(encoded, 'zw');
    });
  });
}
