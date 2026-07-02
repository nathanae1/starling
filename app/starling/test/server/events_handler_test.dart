import 'dart:typed_data';

import 'package:starling/models/encrypted_event.dart';
import 'package:starling/models/envelope.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/server/handlers/events_handler.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_content_key_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftStorageService storage;
  late MockContentKeyService contentKey;
  late Identity identity;

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
    contentKey = MockContentKeyService();
    identity = buildIdentity();
    await storage.saveIdentity(identity);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> get(String path) async {
    final handler = eventsHandler(
      storage: storage,
      contentKey: contentKey,
      identityLookup: () async => identity,
    );
    return handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  Future<Envelope> decode(Response res) async {
    final bytes = Uint8List.fromList(
      await res.read().expand((c) => c).toList(),
    );
    return Envelope.fromBytes(bytes);
  }

  test('returns envelope with version + event items for own events', () async {
    await storage.saveEvent(
      buildEvent(id: 'a', pubkey: identity.pubkey, createdAt: 100),
    );
    await storage.saveEvent(
      buildEvent(id: 'b', pubkey: identity.pubkey, createdAt: 200),
    );
    final res = await get('/events?since=0');
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'application/cbor');

    final envelope = await decode(res);
    expect(envelope.version, kStarlingProtocolVersion);
    expect(envelope.items, hasLength(2));
    for (final item in envelope.items) {
      expect(item.type, 'event');
      final encrypted = EncryptedEvent.fromBytes(item.payload);
      expect(encrypted.pubkey, identity.pubkey);
    }
  });

  test('excludes foreign-pubkey events', () async {
    await storage.saveEvent(
      buildEvent(id: 'mine', pubkey: identity.pubkey, createdAt: 100),
    );
    await storage.saveEvent(
      buildEvent(id: 'theirs', pubkey: 'OTHERPUBKEY', createdAt: 100),
    );
    final envelope = await decode(await get('/events?since=0'));
    expect(envelope.items, hasLength(1));
    final encrypted = EncryptedEvent.fromBytes(envelope.items.first.payload);
    expect(encrypted.pubkey, identity.pubkey);
  });

  test('since filter applied', () async {
    await storage.saveEvent(
      buildEvent(id: 'old', pubkey: identity.pubkey, createdAt: 50),
    );
    await storage.saveEvent(
      buildEvent(id: 'new', pubkey: identity.pubkey, createdAt: 200),
    );
    final envelope = await decode(await get('/events?since=100'));
    expect(envelope.items, hasLength(1));
    final encrypted = EncryptedEvent.fromBytes(envelope.items.first.payload);
    expect(encrypted.createdAt, 200);
  });

  test('invalid since → 400', () async {
    final res = await get('/events?since=abc');
    expect(res.statusCode, 400);
  });

  test('returns 503 when identity is null', () async {
    final handler = eventsHandler(
      storage: storage,
      contentKey: contentKey,
      identityLookup: () async => null,
    );
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/events')),
    );
    expect(res.statusCode, 503);
  });
}
