import 'dart:convert';

import 'package:starling/models/protocol_version.dart';
import 'package:starling/server/handlers/status_handler.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftStorageService storage;

  setUp(() {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> call({Identity? identity}) async {
    final handler = statusHandler(
      storage: storage,
      identityLookup: () async => identity,
    );
    return handler(Request('GET', Uri.parse('http://localhost/status')));
  }

  test('503 when identity is missing', () async {
    final res = await call();
    expect(res.statusCode, 503);
  });

  test('200 with pubkey, version, event_count, media_storage_used', () async {
    final identity = buildIdentity();
    await storage.saveIdentity(identity);
    await storage.saveEvent(buildEvent(id: 'a', pubkey: identity.pubkey));
    await storage.saveEvent(buildEvent(id: 'b', pubkey: identity.pubkey));
    final hash = List.generate(64, (_) => 'a').join();
    await storage.saveMedia(
      CachedMedia(hash: hash, path: '/tmp/a', size: 4096, lastAccessed: 100),
    );

    final res = await call(identity: identity);
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('application/json'));
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['pubkey'], identity.pubkey);
    expect(body['version'], kStarlingProtocolVersion);
    expect(body['event_count'], 2);
    expect(body['media_storage_used'], 4096);
  });
}
