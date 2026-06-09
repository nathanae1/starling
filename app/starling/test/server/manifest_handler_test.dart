import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/server/handlers/manifest_handler.dart';
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
  late Identity identity;

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
    identity = buildIdentity();
    await storage.saveIdentity(identity);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> get(String path, {int pageLimit = 1000}) async {
    final handler = manifestHandler(
      storage: storage,
      identityLookup: () async => identity,
      pageLimit: pageLimit,
    );
    return handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  Map<dynamic, dynamic> decodeBody(Uint8List bytes) =>
      cbor.decode(bytes) as Map<dynamic, dynamic>;

  test('empty DB → empty events, has_older false', () async {
    final res = await get('/manifest?since=0');
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], 'application/cbor');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    expect(body['pubkey'], identity.pubkey);
    expect(body['events'], isEmpty);
    expect(body['has_older'], isFalse);
  });

  test('since/until filters', () async {
    for (var i = 0; i < 5; i++) {
      await storage.saveEvent(
        buildEvent(id: 'e$i', pubkey: identity.pubkey, createdAt: 100 + i),
      );
    }
    final res = await get('/manifest?since=102&until=103');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final events = body['events'] as List<dynamic>;
    expect(events, hasLength(2));
    final ids = events.map((e) => (e as Map)['id']).toSet();
    expect(ids, {'e2', 'e3'});
  });

  test('invalid since → 400', () async {
    final res = await get('/manifest?since=abc');
    expect(res.statusCode, 400);
  });

  test('paging beyond pageLimit sets has_older true', () async {
    for (var i = 0; i < 7; i++) {
      await storage.saveEvent(
        buildEvent(id: 'e$i', pubkey: identity.pubkey, createdAt: 100 + i),
      );
    }
    final res = await get('/manifest?since=0', pageLimit: 5);
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    expect((body['events'] as List<dynamic>), hasLength(5));
    expect(body['has_older'], isTrue);
  });

  test('returns 503 when identity is null', () async {
    final handler = manifestHandler(
      storage: storage,
      identityLookup: () async => null,
    );
    final res =
        await handler(Request('GET', Uri.parse('http://localhost/manifest')));
    expect(res.statusCode, 503);
  });

  // --- Plan 13: rotation distribution piggybacked on /manifest ---

  test('omits new_feed_key when no requester_pubkey is given', () async {
    await storage.addPendingKeyDistribution(
      targetPubkey: 'follower-1',
      encryptedFeedKey: Uint8List.fromList([1, 2, 3]),
      nonce: Uint8List.fromList(List.filled(24, 0xAA)),
      createdAt: 500,
    );
    final res = await get('/manifest');
    expect(res.statusCode, 200);
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    expect(body.containsKey('new_feed_key'), isFalse);
  });

  test('includes new_feed_key when requester has an undelivered row',
      () async {
    await storage.addPendingKeyDistribution(
      targetPubkey: 'follower-1',
      encryptedFeedKey: Uint8List.fromList([1, 2, 3]),
      nonce: Uint8List.fromList(List.filled(24, 0xAA)),
      createdAt: 500,
    );
    final res = await get('/manifest?requester_pubkey=follower-1');
    expect(res.statusCode, 200);
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final newFeedKey = body['new_feed_key'] as Map<dynamic, dynamic>;
    expect(newFeedKey['created_at'], equals(500));
    expect(newFeedKey['encrypted_feed_key'], equals([1, 2, 3]));
    expect(
      (newFeedKey['nonce'] as List<dynamic>).first,
      equals(0xAA),
    );
  });

  test(
      'returns the latest pending row when multiple rotations are stacked',
      () async {
    await storage.addPendingKeyDistribution(
      targetPubkey: 'follower-1',
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    await storage.addPendingKeyDistribution(
      targetPubkey: 'follower-1',
      encryptedFeedKey: Uint8List.fromList([2]),
      nonce: Uint8List.fromList(List.filled(24, 0x02)),
      createdAt: 700,
    );
    final res = await get('/manifest?requester_pubkey=follower-1');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final newFeedKey = body['new_feed_key'] as Map<dynamic, dynamic>;
    expect(newFeedKey['created_at'], equals(700));
  });

  test('ack_rotation_at marks rows delivered; subsequent calls omit new_feed_key',
      () async {
    await storage.addPendingKeyDistribution(
      targetPubkey: 'follower-1',
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    // First call still includes the row (no ack yet).
    final first = await get('/manifest?requester_pubkey=follower-1');
    final firstBody = decodeBody(
      Uint8List.fromList(await first.read().expand((c) => c).toList()),
    );
    expect(firstBody.containsKey('new_feed_key'), isTrue);

    // Now ack the rotation and call again — row is suppressed.
    final second = await get(
      '/manifest?requester_pubkey=follower-1&ack_rotation_at=500',
    );
    final secondBody = decodeBody(
      Uint8List.fromList(await second.read().expand((c) => c).toList()),
    );
    expect(secondBody.containsKey('new_feed_key'), isFalse);
  });

  test('invalid ack_rotation_at → 400', () async {
    final res =
        await get('/manifest?requester_pubkey=follower-1&ack_rotation_at=abc');
    expect(res.statusCode, 400);
  });

  // --- Plan 15: connection card distribution piggybacked on /manifest ---

  test('omits new_connection_card when no requester_pubkey is given',
      () async {
    await storage.queueCardDistribution(
      targetPubkey: 'follower-1',
      cardCbor: Uint8List.fromList([10, 20, 30]),
      sig: Uint8List.fromList(List.filled(64, 0xCC)),
      createdAt: 600,
    );
    final body = decodeBody(
      Uint8List.fromList(
        await (await get('/manifest')).read().expand((c) => c).toList(),
      ),
    );
    expect(body.containsKey('new_connection_card'), isFalse);
  });

  test('includes new_connection_card when requester has an undelivered card',
      () async {
    await storage.queueCardDistribution(
      targetPubkey: 'follower-1',
      cardCbor: Uint8List.fromList([10, 20, 30]),
      sig: Uint8List.fromList(List.filled(64, 0xCC)),
      createdAt: 600,
    );
    final res = await get('/manifest?requester_pubkey=follower-1');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final card = body['new_connection_card'] as Map<dynamic, dynamic>;
    expect(card['created_at'], equals(600));
    expect(card['card_cbor'], equals([10, 20, 30]));
    expect((card['sig'] as List<dynamic>).first, equals(0xCC));
  });

  test('card_seen_at marks card delivered; subsequent calls omit it',
      () async {
    await storage.queueCardDistribution(
      targetPubkey: 'follower-1',
      cardCbor: Uint8List.fromList([10, 20, 30]),
      sig: Uint8List.fromList(List.filled(64, 0xCC)),
      createdAt: 600,
    );
    final first = await get('/manifest?requester_pubkey=follower-1');
    final firstBody = decodeBody(
      Uint8List.fromList(await first.read().expand((c) => c).toList()),
    );
    expect(firstBody.containsKey('new_connection_card'), isTrue);

    final second = await get(
      '/manifest?requester_pubkey=follower-1&card_seen_at=600',
    );
    final secondBody = decodeBody(
      Uint8List.fromList(await second.read().expand((c) => c).toList()),
    );
    expect(secondBody.containsKey('new_connection_card'), isFalse);
  });

  test('invalid card_seen_at → 400', () async {
    final res =
        await get('/manifest?requester_pubkey=follower-1&card_seen_at=abc');
    expect(res.statusCode, 400);
  });
}
