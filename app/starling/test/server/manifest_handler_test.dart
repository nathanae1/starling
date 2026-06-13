import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/server/handlers/manifest_handler.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/manifest_ack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'fixtures.dart';

void main() {
  late SodiumCryptoService crypto;
  late AppDatabase db;
  late DriftStorageService storage;
  late Identity identity;
  late KeyPair ownerKp;
  late KeyPair followerKp;
  late String followerPubkey;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, MockClock());
    ownerKp = await crypto.generateKeyPair();
    followerKp = await crypto.generateKeyPair();
    followerPubkey = crockfordBase32Encode(followerKp.publicKey);
    identity = buildIdentity(pubkey: crockfordBase32Encode(ownerKp.publicKey));
    await storage.saveIdentity(identity);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Response> get(String path, {int pageLimit = 1000}) async {
    final handler = manifestHandler(
      storage: storage,
      crypto: crypto,
      identityLookup: () async => identity,
      pageLimit: pageLimit,
    );
    return handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  Map<dynamic, dynamic> decodeBody(Uint8List bytes) =>
      cbor.decode(bytes) as Map<dynamic, dynamic>;

  /// Register [pubkey] as an accepted inbound follower — pending payloads
  /// are only attached for accepted followers (S4).
  Future<void> seedAcceptedFollower(String pubkey) =>
      storage.saveInboundRequest(FollowRequest(
        pubkey: pubkey,
        payload: Uint8List(0),
        createdAt: 0,
        requestTimestamp: 0,
        status: 'accepted',
      ));

  /// Hex `ack_sig` query value proving [followerKp] acks these values
  /// against the test owner (S3a).
  String ackSig({int ackRotationAt = 0, int cardSeenAt = 0}) =>
      hexEncodeAckSig(signManifestAck(
        crypto,
        requesterSecretKey: followerKp.secretKey,
        ownerPubkey: ownerKp.publicKey,
        ackRotationAt: ackRotationAt,
        cardSeenAt: cardSeenAt,
      ));

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

  test('same-second events page losslessly with until_id (keyset cursor)',
      () async {
    // Three events share one created_at, straddling a page boundary — the
    // old `until = oldest - 1` contract skipped the truncated ones.
    for (final id in ['eA', 'eB', 'eC']) {
      await storage.saveEvent(
        buildEvent(id: id, pubkey: identity.pubkey, createdAt: 100),
      );
    }
    await storage.saveEvent(
      buildEvent(id: 'eD', pubkey: identity.pubkey, createdAt: 200),
    );

    final seen = <String>[];
    String path = '/manifest';
    while (true) {
      final res = await get(path, pageLimit: 2);
      final body = decodeBody(
        Uint8List.fromList(await res.read().expand((c) => c).toList()),
      );
      final events =
          (body['events'] as List<dynamic>).cast<Map<dynamic, dynamic>>();
      seen.addAll(events.map((e) => e['id'] as String));
      if (body['has_older'] != true) break;
      final oldest = events.last;
      path = '/manifest?until=${oldest['created_at']}&until_id=${oldest['id']}';
    }
    // Every id exactly once, (created_at DESC, id DESC) order.
    expect(seen, ['eD', 'eC', 'eB', 'eA']);
  });

  test('bare until keeps the old inclusive semantics', () async {
    for (var i = 0; i < 3; i++) {
      await storage.saveEvent(
        buildEvent(id: 'e$i', pubkey: identity.pubkey, createdAt: 100 + i),
      );
    }
    final res = await get('/manifest?until=101');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final ids =
        (body['events'] as List<dynamic>).map((e) => (e as Map)['id']).toSet();
    expect(ids, {'e0', 'e1'});
  });

  test('returns 503 when identity is null', () async {
    final handler = manifestHandler(
      storage: storage,
      crypto: crypto,
      identityLookup: () async => null,
    );
    final res =
        await handler(Request('GET', Uri.parse('http://localhost/manifest')));
    expect(res.statusCode, 503);
  });

  // --- Plan 13: rotation distribution piggybacked on /manifest ---

  test('omits new_feed_key when no requester_pubkey is given', () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
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
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1, 2, 3]),
      nonce: Uint8List.fromList(List.filled(24, 0xAA)),
      createdAt: 500,
    );
    final res = await get('/manifest?requester_pubkey=$followerPubkey');
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
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([2]),
      nonce: Uint8List.fromList(List.filled(24, 0x02)),
      createdAt: 700,
    );
    final res = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final newFeedKey = body['new_feed_key'] as Map<dynamic, dynamic>;
    expect(newFeedKey['created_at'], equals(700));
  });

  test(
      'signed ack_rotation_at marks rows delivered; subsequent calls omit '
      'new_feed_key', () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    // First call still includes the row (no ack yet).
    final first = await get('/manifest?requester_pubkey=$followerPubkey');
    final firstBody = decodeBody(
      Uint8List.fromList(await first.read().expand((c) => c).toList()),
    );
    expect(firstBody.containsKey('new_feed_key'), isTrue);

    // Now ack the rotation (with possession proof) and call again — the
    // row is suppressed.
    final sig = ackSig(ackRotationAt: 500);
    final second = await get(
      '/manifest?requester_pubkey=$followerPubkey'
      '&ack_rotation_at=500&ack_sig=$sig',
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

  // --- S3a: delivery acks require a possession proof ---

  test('unsigned ack is ignored: rows stay pending', () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    // Spoofed ack without ack_sig — served fine, but nothing is marked.
    final res = await get(
      '/manifest?requester_pubkey=$followerPubkey&ack_rotation_at=999',
    );
    expect(res.statusCode, 200);

    final after = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await after.read().expand((c) => c).toList()),
    );
    expect(body.containsKey('new_feed_key'), isTrue,
        reason: 'unsigned ack must not suppress the pending rotation');
  });

  test('ack signed for different values is ignored', () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    // Sig covers ackRotationAt=100 but the request claims 999.
    final sig = ackSig(ackRotationAt: 100);
    await get(
      '/manifest?requester_pubkey=$followerPubkey'
      '&ack_rotation_at=999&ack_sig=$sig',
    );

    final after = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await after.read().expand((c) => c).toList()),
    );
    expect(body.containsKey('new_feed_key'), isTrue);
  });

  test('malformed ack_sig → 400', () async {
    final res = await get(
      '/manifest?requester_pubkey=$followerPubkey'
      '&ack_rotation_at=500&ack_sig=zz',
    );
    expect(res.statusCode, 400);
  });

  // --- S4: pending payloads only go to current accepted followers ---

  test('non-accepted requester gets neither new_feed_key nor '
      'new_connection_card', () async {
    // Rows exist but the requester is NOT an accepted follower (e.g. they
    // were removed after the rows were queued).
    await storage.addPendingKeyDistribution(
      targetPubkey: followerPubkey,
      encryptedFeedKey: Uint8List.fromList([1]),
      nonce: Uint8List.fromList(List.filled(24, 0x01)),
      createdAt: 500,
    );
    await storage.queueCardDistribution(
      targetPubkey: followerPubkey,
      encryptedCard: Uint8List.fromList([10, 20, 30]),
      nonce: Uint8List.fromList(List.filled(24, 0xCC)),
      createdAt: 600,
    );
    final res = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    expect(body.containsKey('new_feed_key'), isFalse);
    expect(body.containsKey('new_connection_card'), isFalse);
  });

  // --- Plan 15: connection card distribution piggybacked on /manifest ---

  test('omits new_connection_card when no requester_pubkey is given',
      () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.queueCardDistribution(
      targetPubkey: followerPubkey,
      encryptedCard: Uint8List.fromList([10, 20, 30]),
      nonce: Uint8List.fromList(List.filled(24, 0xCC)),
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
    await seedAcceptedFollower(followerPubkey);
    await storage.queueCardDistribution(
      targetPubkey: followerPubkey,
      encryptedCard: Uint8List.fromList([10, 20, 30]),
      nonce: Uint8List.fromList(List.filled(24, 0xCC)),
      createdAt: 600,
    );
    final res = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await res.read().expand((c) => c).toList()),
    );
    final card = body['new_connection_card'] as Map<dynamic, dynamic>;
    expect(card['created_at'], equals(600));
    expect(card['encrypted_card'], equals([10, 20, 30]));
    expect((card['nonce'] as List<dynamic>).first, equals(0xCC));
  });

  test('signed card_seen_at marks card delivered; subsequent calls omit it',
      () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.queueCardDistribution(
      targetPubkey: followerPubkey,
      encryptedCard: Uint8List.fromList([10, 20, 30]),
      nonce: Uint8List.fromList(List.filled(24, 0xCC)),
      createdAt: 600,
    );
    final first = await get('/manifest?requester_pubkey=$followerPubkey');
    final firstBody = decodeBody(
      Uint8List.fromList(await first.read().expand((c) => c).toList()),
    );
    expect(firstBody.containsKey('new_connection_card'), isTrue);

    final sig = ackSig(cardSeenAt: 600);
    final second = await get(
      '/manifest?requester_pubkey=$followerPubkey'
      '&card_seen_at=600&ack_sig=$sig',
    );
    final secondBody = decodeBody(
      Uint8List.fromList(await second.read().expand((c) => c).toList()),
    );
    expect(secondBody.containsKey('new_connection_card'), isFalse);
  });

  test('unsigned card_seen_at does not suppress the pending card', () async {
    await seedAcceptedFollower(followerPubkey);
    await storage.queueCardDistribution(
      targetPubkey: followerPubkey,
      encryptedCard: Uint8List.fromList([10, 20, 30]),
      nonce: Uint8List.fromList(List.filled(24, 0xCC)),
      createdAt: 600,
    );
    // Spoofed ack (no sig) — e.g. an attacker asserting the victim's
    // pubkey with card_seen_at=MAX.
    await get(
      '/manifest?requester_pubkey=$followerPubkey&card_seen_at=999999',
    );

    final after = await get('/manifest?requester_pubkey=$followerPubkey');
    final body = decodeBody(
      Uint8List.fromList(await after.read().expand((c) => c).toList()),
    );
    expect(body.containsKey('new_connection_card'), isTrue,
        reason: 'unsigned card_seen_at must not mark the card delivered');
  });

  test('invalid card_seen_at → 400', () async {
    final res =
        await get('/manifest?requester_pubkey=follower-1&card_seen_at=abc');
    expect(res.statusCode, 400);
  });
}
