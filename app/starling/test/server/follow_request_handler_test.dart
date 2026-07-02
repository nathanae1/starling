import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/server/handlers/follow_request_handler.dart';
import 'package:starling/server/http_server.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_content_key_service.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'fixtures.dart';
import 'http_test_utils.dart';

void main() {
  late AppDatabase db;
  late DriftStorageService storage;
  late MockClock clock;
  late Identity identity;

  setUp(() async {
    db = AppDatabase.memory();
    clock = MockClock(5000);
    storage = DriftStorageService(db, clock);
    identity = buildIdentity();
    await storage.saveIdentity(identity);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> postBytes(Uint8List body) async {
    final handler = followRequestHandler(storage: storage, clock: clock);
    return handler(
      Request('POST', Uri.parse('http://localhost/follow-request'), body: body),
    );
  }

  Uint8List validBody({String pubkey = 'REQUESTER', int timestamp = 4990}) {
    return Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'requester_pubkey': pubkey,
        'encrypted_return_endpoints': Uint8List.fromList(List.filled(64, 1)),
        'nonce': Uint8List.fromList(List.filled(24, 2)),
        'timestamp': timestamp,
      }),
    );
  }

  test('valid CBOR → 202 + row stored', () async {
    final body = validBody();
    final res = await postBytes(body);
    expect(res.statusCode, 202);
    final inbound = await storage.getInboundRequests();
    expect(inbound, hasLength(1));
    expect(inbound.first.pubkey, 'REQUESTER');
    expect(inbound.first.payload, body);
    expect(inbound.first.createdAt, 5000);
    expect(inbound.first.requestTimestamp, 4990);
    expect(inbound.first.status, 'pending');
  });

  test('invalid CBOR → 400', () async {
    final res = await postBytes(Uint8List.fromList([0xff, 0xff, 0xff]));
    expect(res.statusCode, 400);
    expect(await storage.getInboundRequests(), isEmpty);
  });

  test('missing requester_pubkey → 400', () async {
    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'encrypted_return_endpoints': Uint8List(8),
        'nonce': Uint8List(24),
        'timestamp': 1,
      }),
    );
    final res = await postBytes(body);
    expect(res.statusCode, 400);
    expect(await storage.getInboundRequests(), isEmpty);
  });

  test('missing timestamp → 400', () async {
    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'requester_pubkey': 'REQUESTER',
        'encrypted_return_endpoints': Uint8List(8),
        'nonce': Uint8List(24),
      }),
    );
    final res = await postBytes(body);
    expect(res.statusCode, 400);
    expect(await storage.getInboundRequests(), isEmpty);
  });

  test(
    'over-1MB body → 413 (exercises body-size middleware via server)',
    () async {
      final tmpDir = await Directory.systemTemp.createTemp('starling-fr-');
      final server = StarlingHttpServer.social(
        storage: storage,
        contentKey: MockContentKeyService(),
        identityLookup: () async => identity,
        appSupportDir: tmpDir,
        clock: clock,
        crypto: MockCryptoService(),
        signalingInboundHandler: (_) {},
        maxBodyBytes: 1024,
      );
      await server.start();
      addTearDown(() async {
        await server.stop();
        await tmpDir.delete(recursive: true);
      });
      final oversize = List<int>.filled(2048, 0);
      final res = await fetchHttp(
        server.port!,
        '/follow-request',
        method: 'POST',
        body: oversize,
      );
      expect(res.statusCode, 413);
    },
  );
}
