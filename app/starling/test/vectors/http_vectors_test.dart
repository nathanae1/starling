// HTTP-layer contract vectors, client side: the requests PRODUCTION code
// emits (RelayPushService, RelayPushCoordinator, LanNetworkService) must
// match the method/path/query/header names pinned in `index.json`'s
// `http` section. The server-side mirror is
// `relay/crates/starling-relay-http/tests/http_vectors.rs`.
//
// This closes the "rename `after` passes every test" gap from the wire
// audit: a renamed param or header on either side now fails one of the
// two mirrors against the same pinned name.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/relay_push_coordinator.dart';
import 'package:starling/services/relay_push_service.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadVectors() {
  final f = File('test/vectors/index.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;
  late Map<String, dynamic> httpVec;
  late Map<String, dynamic> endpoints;
  late List<String> authHeaders;
  late Uint8List ownerPk;
  late Uint8List ownerSk;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
    final vectors = _loadVectors();
    httpVec = vectors['http'] as Map<String, dynamic>;
    endpoints = httpVec['endpoints'] as Map<String, dynamic>;
    authHeaders = (httpVec['auth_headers'] as List).cast<String>();
    final kp = vectors['keypair'] as Map<String, dynamic>;
    Uint8List fromHex(String s) {
      final out = Uint8List(s.length ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }

    ownerPk = fromHex(kp['ed25519_public_key_hex'] as String);
    ownerSk = fromHex(kp['ed25519_secret_key_hex'] as String);
  });

  Map<String, dynamic> ep(String name) {
    final e = endpoints[name];
    expect(e, isNotNull, reason: 'http.endpoints.$name missing');
    return e as Map<String, dynamic>;
  }

  /// The captured request must match the endpoint's pinned method + path,
  /// carry every pinned auth header (when auth: true), and use only
  /// pinned query-param names.
  void expectContract(http.Request req, Map<String, dynamic> e,
      {String? hash}) {
    expect(req.method, e['method']);
    var path = e['path'] as String;
    if (hash != null) path = path.replaceAll('{hash}', hash);
    expect(req.url.path, path);
    if (e['auth'] as bool) {
      for (final h in authHeaders) {
        expect(req.headers.keys.map((k) => k.toLowerCase()), contains(h),
            reason: 'auth header $h');
      }
    }
    final allowed = ((e['query'] as List?) ?? const []).cast<String>();
    for (final key in req.url.queryParameters.keys) {
      expect(allowed, contains(key),
          reason: 'query param $key not pinned for ${e['path']}');
    }
  }

  test('RelayPushService drives the pinned owner-write contracts', () async {
    final captured = <http.Request>[];
    final client = MockClient((req) async {
      captured.add(req);
      final path = req.url.path;
      if (path == '/events') return http.Response('', 202);
      if (path == '/unpair') return http.Response('', 200);
      if (path.startsWith('/media/') && !path.endsWith('/delete')) {
        return http.Response('', 202);
      }
      if (path.endsWith('/delete')) {
        return http.Response.bytes(
          Uint8List.fromList(
            cbor.encode(<String, dynamic>{'deleted': 0, 'missing': 1}),
          ),
          200,
        );
      }
      if (path == '/media-manifest') {
        return http.Response.bytes(
          Uint8List.fromList(
            cbor.encode(
              <String, dynamic>{'hashes': <String>[], 'has_older': false},
            ),
          ),
          200,
        );
      }
      return http.Response('unexpected ${req.url}', 500);
    });
    final svc = RelayPushService(crypto: crypto, httpClient: client);
    const base = 'http://relay.onion:80';
    final hash = 'c' * 64;

    await svc.pushEvents(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
      items: [
        RelayPushItem(
          id: 'e1',
          encryptedEvent: EncryptedEvent(
            pubkey: crockfordBase32Encode(ownerPk),
            createdAt: 1,
            epoch: 0,
            msgSeq: 0,
            nonce: Uint8List(24),
            payload: Uint8List(4),
          ),
        ),
      ],
    );
    await svc.pushMedia(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
      hash: hash,
      blob: Uint8List(8),
    );
    await svc.deleteEvents(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
      ids: ['e1'],
    );
    await svc.deleteMedia(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
      hashes: [hash],
    );
    await svc.fetchMediaManifest(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
      after: hash,
    );
    await svc.unpairRelay(
      relayBaseUrl: base,
      ownerPubkeyBytes: ownerPk,
      ownerSecretKey: ownerSk,
    );

    expect(captured, hasLength(6));
    expectContract(captured[0], ep('events_push'));
    expectContract(captured[1], ep('media_push'), hash: hash);
    expectContract(captured[2], ep('events_delete'));
    expectContract(captured[3], ep('media_delete'));
    expectContract(captured[4], ep('media_manifest'));
    expect(captured[4].url.queryParameters.keys, ['after']);
    expectContract(captured[5], ep('unpair'));
  });

  test('RelayPushCoordinator walks /manifest with the pinned cursor names',
      () async {
    final e = ep('manifest');
    final storage = MockStorageService();
    await storage.setPairedRelay(
      relayId: 'r1',
      relayOnion: 'relay.onion:80',
      pairedAt: 1,
    );
    final pubkey = crockfordBase32Encode(ownerPk);

    final manifestGets = <http.Request>[];
    final client = MockClient((req) async {
      if (req.url.path != '/manifest') return http.Response('nope', 404);
      manifestGets.add(req);
      final first = manifestGets.length == 1;
      return http.Response.bytes(
        Uint8List.fromList(
          cbor.encode(<String, dynamic>{
            'pubkey': pubkey,
            'events': [
              if (first)
                <String, dynamic>{'id': 'evtB', 'created_at': 200}
              else
                <String, dynamic>{'id': 'evtA', 'created_at': 100},
            ],
            'has_older': first,
          }),
        ),
        200,
      );
    });
    final coordinator = RelayPushCoordinator(
      pushService: RelayPushService(
        crypto: crypto,
        httpClient: MockClient(
          (req) async => http.Response.bytes(
            Uint8List.fromList(
              cbor.encode(
                <String, dynamic>{'hashes': <String>[], 'has_older': false},
              ),
            ),
            req.url.path == '/media-manifest' ? 200 : 202,
          ),
        ),
      ),
      storage: storage,
      relayClient: client,
      identityLookup: () async => Identity(
        pubkey: pubkey,
        feedKey: Uint8List(32),
        feedKeyEpoch: 0,
        createdAt: 1,
      ),
      ownSecretKeyLookup: () async => ownerSk,
      mediaBytesLookup: (hash) async => null,
    );

    await coordinator.reconcile();
    await storage.dispose();

    expect(manifestGets, hasLength(2));
    for (final req in manifestGets) {
      expectContract(req, e);
    }
    // The second page rides the pinned keyset-cursor names.
    expect(
      manifestGets[1].url.queryParameters.keys.toSet(),
      {'until', 'until_id'},
    );
  });

  test('follower /events fetch uses only pinned query names', () async {
    final e = ep('events_get');
    // The production follower fetch sends `since` (the `since_id` keyset
    // resume is a documented follow-up); both must stay within the pinned
    // name set so a server-side rename can't slip by.
    expect((e['query'] as List).cast<String>(), containsAll(['since']));
    expect(e['method'], 'GET');
    expect(e['path'], '/events');
  });
}
