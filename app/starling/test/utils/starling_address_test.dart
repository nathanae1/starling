import 'dart:typed_data';

import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/utils/starling_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 32 bytes of 0x42 → deterministic 52-char Crockford base32 string.
  final pubkey = crockfordBase32Encode(Uint8List(32)..fillRange(0, 32, 0x42));

  test('starlingAddressOf prepends starling://', () {
    expect(starlingAddressOf(pubkey), 'starling://$pubkey');
  });

  test('pubkeyFromStarlingAddress round-trips a valid address', () {
    expect(pubkeyFromStarlingAddress(starlingAddressOf(pubkey)), pubkey);
  });

  test('pubkeyFromStarlingAddress trims whitespace', () {
    expect(pubkeyFromStarlingAddress('  starling://$pubkey  '), pubkey);
  });

  test('pubkeyFromStarlingAddress rejects the invite scheme', () {
    expect(pubkeyFromStarlingAddress('starling://connect?card=AAAA'), isNull);
  });

  test('pubkeyFromStarlingAddress rejects wrong scheme', () {
    expect(pubkeyFromStarlingAddress('https://$pubkey'), isNull);
    expect(pubkeyFromStarlingAddress('starling:$pubkey'), isNull);
  });

  test('pubkeyFromStarlingAddress rejects malformed pubkey', () {
    // Too short.
    expect(pubkeyFromStarlingAddress('starling://abc'), isNull);
    // 'u' is not in the Crockford alphabet (skipped along with i/l/o).
    expect(pubkeyFromStarlingAddress('starling://${'u' * 52}'), isNull);
  });

  test('pubkeyFromStarlingAddress rejects URL with a path', () {
    expect(pubkeyFromStarlingAddress('starling://$pubkey/extra'), isNull);
  });

  test('shortStarlingAddress truncates with ellipsis', () {
    final short = shortStarlingAddress(pubkey);
    expect(short.startsWith('starling://'), isTrue);
    expect(short.contains('…'), isTrue);
    expect(short.length, lessThan(starlingAddressOf(pubkey).length));
  });
}
