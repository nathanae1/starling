import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/connection_card.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/utils/connection_card_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConnectionCard sampleCard() => ConnectionCard(
    pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 7))),
    endpoints: const [Endpoint(type: 'direct', address: '127.0.0.1:54321')],
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

  // --- starling-relay://pair branch (Plan 15) ---

  String relayPairUrl({
    String onion = 'exampleadminonion.onion',
    List<int>? token,
    String version = '0.1.0',
  }) {
    final cardCbor = cbor.encode(<String, dynamic>{
      'relay_onion': onion,
      'pairing_token': Uint8List.fromList(token ?? List.filled(32, 0x42)),
      'relay_version': version,
    });
    final b64 = base64Url.encode(cardCbor).replaceAll('=', '');
    return 'starling-relay://pair?card=$b64';
  }

  test('parses a starling-relay://pair URL into ValidRelayPair', () {
    final parsed = parseInvite(relayPairUrl());
    expect(parsed, isA<ValidRelayPair>());
    final payload = (parsed as ValidRelayPair).payload;
    expect(payload.relayOnion, 'exampleadminonion.onion');
    expect(payload.pairingToken, hasLength(32));
    expect(payload.pairingToken.toSet(), {0x42});
    expect(payload.relayVersion, '0.1.0');
  });

  test('relay pair URL survives surrounding whitespace', () {
    expect(parseInvite('  ${relayPairUrl()}\n'), isA<ValidRelayPair>());
  });

  test('relay pair URL without card param is invalid', () {
    final result = parseInvite('starling-relay://pair');
    expect(result, isA<InvalidInvite>());
    expect((result as InvalidInvite).reason, contains('card'));
  });

  test('relay pair card missing fields is invalid, not a crash', () {
    // Valid CBOR map, but no relay_onion/pairing_token/relay_version.
    final b64 = base64Url
        .encode(cbor.encode(<String, dynamic>{'nope': 1}))
        .replaceAll('=', '');
    final result = parseInvite('starling-relay://pair?card=$b64');
    expect(result, isA<InvalidInvite>());
  });

  test('relay pair card that is not CBOR is invalid, not a crash', () {
    final b64 = base64Url.encode([1, 2, 3]).replaceAll('=', '');
    expect(
      parseInvite('starling-relay://pair?card=$b64'),
      isA<InvalidInvite>(),
    );
  });

  test('a relay pair card never parses as a friend invite (and vice versa)',
      () {
    // The same base64 payload under the friend scheme must NOT come back
    // as a relay pairing (the two flows must never cross).
    final b64 = Uri.parse(relayPairUrl()).queryParameters['card']!;
    final asFriend = parseInvite('starling://connect?card=$b64');
    expect(asFriend, isA<InvalidInvite>());

    final friendB64 = Uri.parse(
      inviteUrlFor(sampleCard()),
    ).queryParameters['card']!;
    final asRelay = parseInvite('starling-relay://pair?card=$friendB64');
    expect(asRelay, isA<InvalidInvite>());
  });
}
