import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:starling/server/http_server.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_content_key_service.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'http_test_utils.dart';

class _SequenceRandom implements Random {
  _SequenceRandom(this._values);
  final List<int> _values;
  int _idx = 0;
  @override
  int nextInt(int max) {
    final v = _values[_idx % _values.length];
    _idx++;
    return v % max;
  }

  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

void main() {
  late AppDatabase db;
  late DriftStorageService storage;
  late Directory tmpDir;
  late Identity identity;

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
    tmpDir = await Directory.systemTemp.createTemp('starling-server-test-');
    identity = buildIdentity();
    await storage.saveIdentity(identity);
  });

  tearDown(() async {
    await db.close();
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  StarlingHttpServer makeServer({
    Random? random,
    int rateLimitPerMinute = 120,
  }) {
    return StarlingHttpServer.social(
      storage: storage,
      contentKey: MockContentKeyService(),
      identityLookup: () async => identity,
      appSupportDir: tmpDir,
      clock: MockClock(),
      crypto: MockCryptoService(),
      signalingInboundHandler: (_) {},
      rateLimitPerMinute: rateLimitPerMinute,
      random: random,
    );
  }

  test('binds to a port in the ephemeral range', () async {
    final server = makeServer();
    await server.start();
    addTearDown(server.stop);
    expect(server.port, isNotNull);
    expect(server.port!, inInclusiveRange(49152, 65535));
    expect(server.isRunning, isTrue);
  });

  test('retries on bind conflict', () async {
    // Pre-bind a known port on the same address the server uses
    // (anyIPv4) to force the first attempt to fail. Loopback would let the
    // server bind 0.0.0.0:port via SO_REUSEADDR on macOS.
    final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(blocker.close);
    final blockedPort = blocker.port;
    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final freePort = probe.port;
    await probe.close();
    if (blockedPort < 49152 || freePort < 49152) return; // skip if outside

    const base = 49152;
    const range = 65535 - 49152 + 1;
    final random = _SequenceRandom([
      (blockedPort - base) % range,
      (freePort - base) % range,
    ]);
    final server = makeServer(random: random);
    await server.start();
    addTearDown(server.stop);
    expect(server.port, freePort);
  });

  test('stop releases the port', () async {
    final server = makeServer();
    await server.start();
    final port = server.port!;
    await server.stop();
    expect(server.isRunning, isFalse);
    expect(server.port, isNull);

    // Re-binding the same port should now succeed.
    final s2 = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await s2.close();
  });

  test('curl-equivalent /status returns valid JSON', () async {
    final server = makeServer();
    await server.start();
    addTearDown(server.stop);
    final res = await fetchHttp(server.port!, '/status');
    expect(res.statusCode, 200);
    final body = jsonDecode(utf8.decode(res.body)) as Map<String, dynamic>;
    expect(body['pubkey'], identity.pubkey);
  });

  test('rate limit triggers 429 after the configured number of hits', () async {
    final server = makeServer(rateLimitPerMinute: 3);
    await server.start();
    addTearDown(server.stop);
    for (var i = 0; i < 3; i++) {
      final ok = await fetchHttp(server.port!, '/status');
      expect(ok.statusCode, 200);
    }
    final blocked = await fetchHttp(server.port!, '/status');
    expect(blocked.statusCode, 429);
  });
}
