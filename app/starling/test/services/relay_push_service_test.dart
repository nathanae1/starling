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

  /// Verify the request-bound owner signature (M2 scheme) on a captured
  /// request: sig over ownerRequestDigest(method, path, ts, body).
  void expectBoundSig(
    http.Request captured,
    Uint8List publicKey, {
    required String method,
    required String path,
    Uint8List? body,
  }) {
    expect(
      captured.headers['x-starling-pubkey'],
      equals(base64.encode(publicKey)),
    );
    final ts = int.parse(captured.headers['x-starling-ts']!);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect((now - ts).abs(), lessThan(60), reason: 'ts is fresh');
    final digest = ownerRequestDigest(
      crypto: crypto,
      method: method,
      path: path,
      unixTs: ts,
      body: body ?? captured.bodyBytes,
    );
    final sig = base64.decode(captured.headers['x-starling-sig']!);
    expect(crypto.verify(publicKey, digest, sig), isTrue);
  }

  test('pushEvents posts CBOR {items:[{id,payload}]} with a verifiable '
      'request-bound owner signature', () async {
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
    expectBoundSig(captured, kp.publicKey, method: 'POST', path: '/events');

    // The bound digest is NOT the legacy body-only digest.
    final legacySig = base64.decode(captured.headers['x-starling-sig']!);
    expect(
      crypto.verify(
        kp.publicKey,
        crypto.blake2b256(captured.bodyBytes),
        legacySig,
      ),
      isFalse,
    );

    final decoded = cbor.decode(captured.bodyBytes) as Map<dynamic, dynamic>;
    final items = decoded['items'] as List<dynamic>;
    expect(items, hasLength(1));
    expect((items.first as Map)['id'], equals('evt-1'));
  });

  test(
    'pushMedia posts the raw blob to /media/<hash> with bound owner-sig '
    'headers',
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
      expectBoundSig(
        captured,
        kp.publicKey,
        method: 'POST',
        path: '/media/${'a' * 64}',
      );
    },
  );

  test('fetchMediaManifest signs the empty body against its own path', () async {
    final kp = await crypto.generateKeyPair();
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response.bytes(
        Uint8List.fromList(
          cbor.encode(<String, dynamic>{'hashes': <String>[], 'has_older': false}),
        ),
        200,
      );
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);

    await svc.fetchMediaManifest(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
    );
    expectBoundSig(
      captured,
      kp.publicKey,
      method: 'GET',
      path: '/media-manifest',
      body: Uint8List(0),
    );
  });

  test('pushEvents throws on a non-202 response, carrying the status code',
      () async {
    final kp = await crypto.generateKeyPair();
    final client = MockClient((req) async => http.Response('nope', 507));
    final svc = RelayPushService(crypto: crypto, httpClient: client);
    expect(
      () => svc.pushEvents(
        relayBaseUrl: 'http://relay.onion:80',
        ownerPubkeyBytes: kp.publicKey,
        ownerSecretKey: kp.secretKey,
        items: [RelayPushItem(id: 'x', encryptedEvent: sampleEvent())],
      ),
      throwsA(
        isA<RelayPushException>().having(
          (e) => e.statusCode,
          'statusCode',
          507,
        ),
      ),
    );
  });

  test('deleteEvents posts CBOR {ids:[...]} to /events/delete and decodes '
      'the receipt', () async {
    final kp = await crypto.generateKeyPair();
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response.bytes(
        Uint8List.fromList(
          cbor.encode(<String, dynamic>{'deleted': 2, 'missing': 1}),
        ),
        200,
        headers: {'content-type': 'application/cbor'},
      );
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);

    final receipt = await svc.deleteEvents(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
      ids: ['evt-1', 'evt-2', 'evt-3'],
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/events/delete');
    expectBoundSig(
      captured,
      kp.publicKey,
      method: 'POST',
      path: '/events/delete',
    );
    final decoded = cbor.decode(captured.bodyBytes) as Map<dynamic, dynamic>;
    expect(decoded['ids'], equals(['evt-1', 'evt-2', 'evt-3']));
    expect(receipt.deleted, 2);
    expect(receipt.missing, 1);
  });

  test('deleteMedia posts CBOR {hashes:[...]} to /media/delete; empty list '
      'is a local no-op', () async {
    final kp = await crypto.generateKeyPair();
    var requests = 0;
    late http.Request captured;
    final client = MockClient((req) async {
      requests++;
      captured = req;
      return http.Response.bytes(
        Uint8List.fromList(
          cbor.encode(<String, dynamic>{'deleted': 1, 'missing': 0}),
        ),
        200,
      );
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);

    final noop = await svc.deleteMedia(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
      hashes: const [],
    );
    expect(noop.deleted, 0);
    expect(requests, 0, reason: 'empty delete never hits the wire');

    final receipt = await svc.deleteMedia(
      relayBaseUrl: 'http://relay.onion:80',
      ownerPubkeyBytes: kp.publicKey,
      ownerSecretKey: kp.secretKey,
      hashes: ['a' * 64],
    );
    expect(captured.url.path, '/media/delete');
    expectBoundSig(
      captured,
      kp.publicKey,
      method: 'POST',
      path: '/media/delete',
    );
    expect(receipt.deleted, 1);
  });

  test('deleteEvents throws with statusCode on a non-200 response', () async {
    final kp = await crypto.generateKeyPair();
    final client = MockClient((req) async => http.Response('nope', 401));
    final svc = RelayPushService(crypto: crypto, httpClient: client);
    expect(
      () => svc.deleteEvents(
        relayBaseUrl: 'http://relay.onion:80',
        ownerPubkeyBytes: kp.publicKey,
        ownerSecretKey: kp.secretKey,
        ids: ['evt-1'],
      ),
      throwsA(
        isA<RelayPushException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });
}
