import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/models/models.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/comment_service.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
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
    required this.contentKey,
    required this.clock,
    required this.service,
  });
  final AppDatabase db;
  final StorageService storage;
  final Identity identity;
  final PairwiseContentKeyService contentKey;
  final _FixedClock clock;
  final CommentService service;
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
  final service = DefaultCommentService(
    contentKey: contentKey,
    storage: storage,
    clock: clock,
    identityLookup: () async => identity,
  );
  return _Fixture(
    db: db,
    storage: storage,
    identity: identity,
    contentKey: contentKey,
    clock: clock,
    service: service,
  );
}

Future<String> _seedPost(
  StorageService storage,
  String authorPubkey, {
  int createdAt = 1_700_000_000,
  String id = 'post-1',
}) async {
  final post = Event(
    version: '2026-03-24',
    id: id,
    pubkey: authorPubkey,
    createdAt: createdAt,
    kind: EventKind.post,
    content: Uint8List.fromList(utf8.encode('hi')),
    sig: Uint8List(64),
  );
  await storage.saveEvent(post);
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('CommentService.create', () {
    test('comment on own post: stored locally, NOT enqueued', () async {
      final f = await _buildFixture(crypto);
      final postId = await _seedPost(f.storage, f.identity.pubkey);

      final commentId = await f.service.create(
        targetPostId: postId,
        text: 'first!',
      );

      final stored = await f.storage.getEvent(commentId);
      expect(stored, isNotNull);
      expect(stored!.kind, equals(EventKind.comment));
      expect(stored.ref, equals(postId));
      expect(stored.pubkey, equals(f.identity.pubkey));
      expect(utf8.decode(stored.content), equals('first!'));

      // No outbound queue entry — author == self.
      final queued = await f.storage.dequeue(f.identity.pubkey);
      expect(queued, isEmpty);

      await f.db.close();
    });

    test(
      'comment on a third-party post: stored locally AND enqueued for the author',
      () async {
        final f = await _buildFixture(crypto);
        const friendPubkey = 'FRIEND-PUBKEY-XYZ';
        final postId = await _seedPost(f.storage, friendPubkey);

        final commentId = await f.service.create(
          targetPostId: postId,
          text: 'love this',
        );

        // Local copy.
        final stored = await f.storage.getEvent(commentId);
        expect(stored, isNotNull);
        expect(stored!.ref, equals(postId));

        // Queued for delivery to the friend.
        final queued = await f.storage.dequeue(friendPubkey);
        expect(queued, hasLength(1));
        expect(queued.first.targetPubkey, equals(friendPubkey));
        expect(queued.first.eventBlob.length, greaterThan(0));

        // The blob is a CBOR-encoded EncryptedEvent; decoding it round-trips
        // through decrypt.
        final encrypted = EncryptedEvent.fromBytes(queued.first.eventBlob);
        final plain = f.contentKey.decryptEvent(encrypted, f.identity.feedKey);
        expect(plain.id, equals(commentId));
        expect(plain.kind, equals(EventKind.comment));

        await f.db.close();
      },
    );

    test('comment on an unknown postId: stored locally, NOT enqueued '
        '(no author lookup possible)', () async {
      final f = await _buildFixture(crypto);

      final commentId = await f.service.create(
        targetPostId: 'never-seen',
        text: 'huh',
      );
      expect(await f.storage.getEvent(commentId), isNotNull);

      final allQueued = await f.db.outboundQueueDao.dequeue('never-seen');
      expect(allQueued, isEmpty);

      await f.db.close();
    });
  });

  group('CommentService.delete', () {
    test('produces a kind=6 with ref=commentId', () async {
      final f = await _buildFixture(crypto);
      final postId = await _seedPost(f.storage, f.identity.pubkey);
      final commentId = await f.service.create(
        targetPostId: postId,
        text: 'hi',
      );

      final tombId = await f.service.delete(commentId);
      final tomb = await f.storage.getEvent(tombId);
      expect(tomb, isNotNull);
      expect(tomb!.kind, equals(EventKind.delete));
      expect(tomb.ref, equals(commentId));

      await f.db.close();
    });

    test('delete a comment that was on a friend\'s post: queues the '
        'tombstone for the friend', () async {
      final f = await _buildFixture(crypto);
      const friendPubkey = 'FRIEND';
      final postId = await _seedPost(f.storage, friendPubkey);
      final commentId = await f.service.create(
        targetPostId: postId,
        text: 'oops',
      );

      // First entry is the comment; deletion adds a tombstone for the friend.
      final beforeQueue = await f.storage.dequeue(friendPubkey);
      expect(beforeQueue, hasLength(1));

      await f.service.delete(commentId);

      final afterQueue = await f.storage.dequeue(friendPubkey);
      expect(afterQueue.length, equals(2));

      await f.db.close();
    });
  });
}
