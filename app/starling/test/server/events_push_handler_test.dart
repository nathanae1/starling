import 'dart:typed_data';

import 'package:starling/models/encrypted_event.dart';
import 'package:starling/models/envelope.dart';
import 'package:starling/models/event.dart';
import 'package:starling/models/event_kind.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/server/handlers/events_push_handler.dart';
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

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
    contentKey = MockContentKeyService();
    await storage.saveIdentity(buildIdentity());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> postBytes(Uint8List body) async {
    final handler = eventsPushHandler(
      storage: storage,
      contentKey: contentKey,
      clock: MockClock(),
    );
    return handler(
      Request('POST', Uri.parse('http://localhost/events'), body: body),
    );
  }

  EncryptedEvent buildEncryptedEvent(String pubkey, String id) {
    final event = Event(
      version: kStarlingProtocolVersion,
      id: id,
      pubkey: pubkey,
      createdAt: 100,
      kind: EventKind.comment,
      ref: 'some-post',
      content: Uint8List.fromList('hi'.codeUnits),
      sig: Uint8List(64),
    );
    return contentKey.encryptEvent(
      event,
      Uint8List.fromList(List.filled(32, 0xAA)),
      0,
      0,
    );
  }

  test('empty body → 400', () async {
    final res = await postBytes(Uint8List(0));
    expect(res.statusCode, 400);
  });

  test('non-CBOR body → 400', () async {
    final res = await postBytes(Uint8List.fromList([0xFF, 0xFE, 0xFD]));
    expect(res.statusCode, 400);
  });

  test('events from a known follow are accepted and stored', () async {
    const friendPubkey = 'FRIEND-PUBKEY-A';
    await storage.saveFollow(
      Follow(
        pubkey: friendPubkey,
        connectionCard: '{}',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
      ),
    );

    final encrypted = buildEncryptedEvent(friendPubkey, 'comment-1');
    final envelope = Envelope(
      version: kStarlingProtocolVersion,
      items: [EnvelopeItem(type: 'event', payload: encrypted.toBytes())],
    );

    final res = await postBytes(envelope.toBytes());
    expect(res.statusCode, 202);

    final stored = await storage.getEvent('comment-1');
    expect(stored, isNotNull);
    expect(stored!.kind, equals(EventKind.comment));
    expect(stored.pubkey, equals(friendPubkey));
  });

  test(
    'events from a NON-followed pubkey are silently dropped (still 202)',
    () async {
      final encrypted = buildEncryptedEvent('STRANGER-PUBKEY', 'mystery-1');
      final envelope = Envelope(
        version: kStarlingProtocolVersion,
        items: [EnvelopeItem(type: 'event', payload: encrypted.toBytes())],
      );

      final res = await postBytes(envelope.toBytes());
      expect(res.statusCode, 202);
      expect(await storage.getEvent('mystery-1'), isNull);
    },
  );

  test('mixed envelope: known follow accepted, stranger dropped', () async {
    const friendPubkey = 'FRIEND-PUBKEY-B';
    await storage.saveFollow(
      Follow(
        pubkey: friendPubkey,
        connectionCard: '{}',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
      ),
    );

    final friendEvent = buildEncryptedEvent(friendPubkey, 'good');
    final strangerEvent = buildEncryptedEvent('NOT-A-FRIEND', 'bad');

    final envelope = Envelope(
      version: kStarlingProtocolVersion,
      items: [
        EnvelopeItem(type: 'event', payload: friendEvent.toBytes()),
        EnvelopeItem(type: 'event', payload: strangerEvent.toBytes()),
      ],
    );

    final res = await postBytes(envelope.toBytes());
    expect(res.statusCode, 202);
    expect(await storage.getEvent('good'), isNotNull);
    expect(await storage.getEvent('bad'), isNull);
  });
}
