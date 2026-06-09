import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/models/encrypted_event.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/relay_push_service.dart';

void main() {
  late SodiumCryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  EncryptedEvent sampleEvent() => EncryptedEvent(
        pubkey: 'AUTHOR',
        createdAt: 100,
        epoch: 0,
        msgSeq: 3,
        nonce: Uint8List.fromList(List.filled(24, 0x11)),
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

  test('pushEvents posts CBOR {items:[{id,payload}]} with a verifiable '
      'owner signature over the body', () async {
    final kp = await crypto.generateKeyPair();
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('', 202);
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);

    await svc.pushEvents(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
      items: [RelayPushItem(id: 'evt-1', encryptedEvent: sampleEvent())],
    );

    expect(captured.method, 'POST');
    expect(captured.url.host, 'relay.onion');
    expect(captured.url.path, '/events');
    expect(captured.headers['content-type'], contains('application/cbor'));
    expect(captured.headers['x-starling-pubkey'],
        equals(base64.encode(kp.publicKey)));

    // The signature must verify against blake2b256(body) under the owner key.
    final body = captured.bodyBytes;
    final digest = crypto.blake2b256(body);
    final sig = base64.decode(captured.headers['x-starling-sig']!);
    expect(crypto.verify(kp.publicKey, digest, sig), isTrue);

    final decoded = cbor.decode(body) as Map<dynamic, dynamic>;
    final items = decoded['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect((items.first as Map)['id'], equals('evt-1'));
  });

  test('pushMedia posts the raw blob to /media/<hash> with owner-sig headers',
      () async {
    final kp = await crypto.generateKeyPair();
    final blob = Uint8List.fromList([9, 8, 7, 6, 5]);
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('', 202);
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);

    await svc.pushMedia(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
      hash: 'a' * 64,
      blob: blob,
    );

    expect(captured.url.host, 'relay.onion');
    expect(captured.url.path, '/media/${'a' * 64}');
    expect(captured.bodyBytes, equals(blob));
    final sig = base64.decode(captured.headers['x-starling-sig']!);
    expect(crypto.verify(kp.publicKey, crypto.blake2b256(blob), sig), isTrue);
  });

  test('pushEvents throws on a non-202 response', () async {
    final kp = await crypto.generateKeyPair();
    final client = MockClient((req) async => http.Response('nope', 401));
    final svc = RelayPushService(crypto: crypto, httpClient: client);
    expect(
      () => svc.pushEvents(
        relayBaseUrl: 'http://relay.onion:80',
        ownerPubkeyBytes: kp.publicKey,
        ownerSecretKey: kp.secretKey,
        items: [RelayPushItem(id: 'x', encryptedEvent: sampleEvent())],
      ),
      throwsA(isA<RelayPushException>()),
    );
  });
}
