import 'dart:typed_data';

import 'package:starling/models/connection_card.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/utils/connection_card_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConnectionCard sampleCard() => ConnectionCard(
        pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 7))),
        endpoints: const [
          Endpoint(type: 'direct', address: '127.0.0.1:54321'),
        ],
      );

  test('parses a starling://connect URL', () {
    final card = sampleCard();
    final url = inviteUrlFor(card);
    final parsed = parseInvite(url);
    expect(parsed, isA<ValidInvite>());
    expect((parsed as ValidInvite).card.pubkey, card.pubkey);
    expect(parsed.card.endpoints, card.endpoints);
  });

  test('parses bare base64url payload', () {
    final card = sampleCard();
    final url = inviteUrlFor(card);
    final bare = Uri.parse(url).queryParameters['card']!;
    final parsed = parseInvite(bare);
    expect(parsed, isA<ValidInvite>());
    expect((parsed as ValidInvite).card.pubkey, card.pubkey);
  });

  test('strips whitespace before parsing', () {
    final card = sampleCard();
    final url = inviteUrlFor(card);
    final padded = '   $url\n';
    expect(parseInvite(padded), isA<ValidInvite>());
  });

  test('rejects empty input', () {
    expect(parseInvite(''), isA<InvalidInvite>());
    expect(parseInvite('   '), isA<InvalidInvite>());
  });

  test('rejects non-starling scheme', () {
    final result = parseInvite('https://example.com/?card=xyz');
    expect(result, isA<InvalidInvite>());
    expect((result as InvalidInvite).reason, contains('not a starling invite'));
  });

  test('rejects URL without card param', () {
    final result = parseInvite('starling://connect');
    expect(result, isA<InvalidInvite>());
    expect((result as InvalidInvite).reason, contains('card'));
  });

  test('rejects malformed base64url', () {
    final result = parseInvite('starling://connect?card=!!!notbase64!!!');
    expect(result, isA<InvalidInvite>());
  });

  test('rejects valid base64 that is not a ConnectionCard', () {
    final result = parseInvite('starling://connect?card=AAAAAAAA');
    expect(result, isA<InvalidInvite>());
  });

  test('rejects card with malformed pubkey', () {
    // Pubkey that decodes to fewer than 32 bytes.
    final card = ConnectionCard(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(8, 1))),
    );
    final url = inviteUrlFor(card);
    final result = parseInvite(url);
    expect(result, isA<InvalidInvite>());
  });
}
