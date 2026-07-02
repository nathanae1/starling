import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/models/models.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/reaction_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock implements Clock {
  _FixedClock(this.value);
  int value;
  @override
  int nowUnixSeconds() => value;
}

class _Fixture {
  _Fixture({
    required this.db,
    required this.storage,
    required this.identity,
    required this.clock,
    required this.service,
  });
  final AppDatabase db;
  final StorageService storage;
  final Identity identity;
  final _FixedClock clock;
  final ReactionService service;
}

Future<_Fixture> _buildFixture(
  CryptoService crypto, {
  int now = 1_700_000_000,
}) async {
  final db = AppDatabase.memory();
  final kp = await crypto.generateKeyPair();
  final pubkey = crockfordBase32Encode(kp.publicKey);
  final feedKey = crypto.randomBytes(32);
  await db.identityDao.upsertIdentity(
    IdentityEntriesCompanion.insert(
      pubkey: pubkey,
      feedKey: feedKey,
      recoveryPhrase: const Value(null),
      createdAt: now,
    ),
  );
  final cache = FeedKeyCache()..put(pubkey, feedKey, 0);
  final clock = _FixedClock(now);
  final storage = DriftStorageService(db, clock);
  final contentKey = PairwiseContentKeyService(
    crypto: crypto,
    cache: cache,
    ownPubkey: pubkey,
    ownSecretKey: kp.secretKey,
  );
  final identity = Identity(
    pubkey: pubkey,
    feedKey: feedKey,
    feedKeyEpoch: 0,
    createdAt: now,
  );
  final service = DefaultReactionService(
    contentKey: contentKey,
    storage: storage,
    clock: clock,
    identityLookup: () async => identity,
  );
  return _Fixture(
    db: db,
    storage: storage,
    identity: identity,
    clock: clock,
    service: service,
  );
}

Future<String> _seedPost(StorageService storage, String authorPubkey) async {
  final post = Event(
    version: '2026-03-24',
    id: 'post-${authorPubkey.length}',
    pubkey: authorPubkey,
    createdAt: 1_700_000_000,
    kind: EventKind.post,
    content: Uint8List.fromList(utf8.encode('hi')),
    sig: Uint8List(64),
  );
  await storage.saveEvent(post);
  return post.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  test('like creates a kind=5 event referencing the post', () async {
    final f = await _buildFixture(crypto);
    final postId = await _seedPost(f.storage, f.identity.pubkey);

    final likeId = await f.service.like(postId);
    final like = await f.storage.getEvent(likeId);
    expect(like, isNotNull);
    expect(like!.kind, equals(EventKind.like));
    expect(like.ref, equals(postId));
    expect(like.pubkey, equals(f.identity.pubkey));

    await f.db.close();
  });

  test('like is idempotent: re-liking returns the same id without a new '
      'event', () async {
    final f = await _buildFixture(crypto);
    final postId = await _seedPost(f.storage, f.identity.pubkey);

    final id1 = await f.service.like(postId);
    f.clock.value += 5;
    final id2 = await f.service.like(postId);
    expect(id1, equals(id2));

    final all = await f.storage.getEventsByRef(postId, kind: EventKind.like);
    expect(all, hasLength(1));

    await f.db.close();
  });

  test('unlike emits kind=6 referencing the like; isLikedByMe flips back '
      'to false', () async {
    final f = await _buildFixture(crypto);
    final postId = await _seedPost(f.storage, f.identity.pubkey);

    await f.service.like(postId);
    expect(await f.service.isLikedByMe(postId), isTrue);

    f.clock.value += 1;
    final tombId = await f.service.unlike(postId);
    expect(tombId, isNotNull);
    final tomb = await f.storage.getEvent(tombId!);
    expect(tomb!.kind, equals(EventKind.delete));
    expect(await f.service.isLikedByMe(postId), isFalse);

    await f.db.close();
  });

  test('like → unlike → like creates a fresh kind=5 (not idempotent across '
      'tombstone)', () async {
    final f = await _buildFixture(crypto);
    final postId = await _seedPost(f.storage, f.identity.pubkey);

    final id1 = await f.service.like(postId);
    f.clock.value += 1;
    await f.service.unlike(postId);
    f.clock.value += 1;
    final id2 = await f.service.like(postId);
    expect(id1, isNot(equals(id2)));
    expect(await f.service.isLikedByMe(postId), isTrue);

    await f.db.close();
  });

  test('like on someone else\'s post enqueues for that author', () async {
    final f = await _buildFixture(crypto);
    const friend = 'FRIEND-PK';
    final postId = await _seedPost(f.storage, friend);
    await f.service.like(postId);

    final queued = await f.storage.dequeue(friend);
    expect(queued, hasLength(1));

    await f.db.close();
  });

  test('unlike on a follow\'s post also enqueues the tombstone', () async {
    final f = await _buildFixture(crypto);
    const friend = 'FRIEND-PK';
    final postId = await _seedPost(f.storage, friend);
    await f.service.like(postId);
    f.clock.value += 1;
    await f.service.unlike(postId);

    final queued = await f.storage.dequeue(friend);
    expect(queued.length, equals(2));

    await f.db.close();
  });
}
