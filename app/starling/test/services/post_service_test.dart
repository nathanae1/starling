import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/media_service.dart';
import 'package:starling/services/post_service.dart';
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

class _StubMediaService implements MediaService {
  _StubMediaService(this._result);
  final MediaProcessingResult _result;
  int calls = 0;
  Uint8List? lastPhoto;
  Uint8List? lastMsgKey;

  @override
  Future<MediaProcessingResult> processAndStoreOwnPhoto({
    required Uint8List photoBytes,
    required Uint8List msgKey,
    int maxDimension = 1080,
    bool square = false,
  }) async {
    calls++;
    lastPhoto = photoBytes;
    lastMsgKey = msgKey;
    return _result;
  }

  @override
  Future<Uint8List?> readPlaintext(String hexHash, Uint8List msgKey) async =>
      null;

  @override
  Future<void> storeReceivedBlob(
    String hexHash,
    Uint8List encryptedBytes,
  ) async {}

  @override
  Future<bool> hasBlobOnDisk(String hexHash) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  Future<_Fixture> buildFixture({int now = 1_712_500_000}) async {
    final db = AppDatabase.memory();
    final kp = await crypto.generateKeyPair();
    final pubkey = crockfordBase32Encode(kp.publicKey);
    final feedKey = crypto.randomBytes(32);
    // Seed identity so DriftStorageService.saveEvent resolves isOwn=1.
    await db.identityDao.upsertIdentity(IdentityEntriesCompanion.insert(
      pubkey: pubkey,
      feedKey: feedKey,
      recoveryPhrase: const Value(null),
      createdAt: now,
    ));
    final cache = FeedKeyCache()..put(pubkey, feedKey, 0);
    final clock = _FixedClock(now);
    final storage = DriftStorageService(db, clock);
    final contentKey = PairwiseContentKeyService(
      crypto: crypto,
      cache: cache,
      ownPubkey: pubkey,
      ownSecretKey: kp.secretKey,
    );
    final media = _StubMediaService(MediaProcessingResult(
      compressedHash: 'cc' * 32,
      compressedSize: 1234,
      compressedMime: 'image/jpeg',
      originalHash: 'dd' * 32,
      originalSize: 9999,
      originalMime: 'image/jpeg',
    ));
    final identity = Identity(
      pubkey: pubkey,
      feedKey: feedKey,
      feedKeyEpoch: 0,
      createdAt: now,
    );
    final service = DefaultPostService(
      contentKey: contentKey,
      crypto: crypto,
      storage: storage,
      media: media,
      clock: clock,
      identityLookup: () async => storage.getIdentity(),
    );
    return _Fixture(
      db: db,
      storage: storage,
      crypto: crypto,
      service: service,
      media: media,
      clock: clock,
      identity: identity,
      ownPublicKey: kp.publicKey,
    );
  }

  group('createPost', () {
    test('persists a kind=1 event with is_own=1 and the expected fields',
        () async {
      final f = await buildFixture();
      final photo = Uint8List.fromList(List.generate(100, (i) => i));
      final id = await f.service.createPost(
        photoBytes: photo,
        caption: 'hello starling',
      );

      expect(id, isNotEmpty);
      expect(f.media.calls, equals(1));
      expect(f.media.lastPhoto, equals(photo));
      // Media is encrypted with a per-message key derived from the
      // identity's chain root + the msg_seq allocated by the publisher
      // (0 on the first publish).
      expect(
        f.media.lastMsgKey,
        equals(deriveMsgKey(f.identity.feedKey, 0, f.crypto)),
      );

      final stored = await f.storage.getEvent(id);
      expect(stored, isNotNull);
      expect(stored!.kind, equals(EventKind.post));
      expect(stored.pubkey, equals(f.identity.pubkey));
      expect(stored.createdAt, equals(f.clock.value));
      expect(stored.ref, isNull);
      expect(utf8.decode(stored.content), equals('hello starling'));
      expect(stored.media.length, equals(1));
      expect(stored.media.first.hash, equals('cc' * 32));
      expect(stored.media.first.mimeType, equals('image/jpeg'));
      expect(stored.media.first.size, equals(1234));
      expect(stored.version, equals(kStarlingProtocolVersion));
      expect(stored.extensions, isEmpty);
      expect(stored.sig.length, equals(64));

      // is_own is not on the Event model (it's a storage-only column). Verify
      // via the DAO directly.
      final row = await f.db.eventsDao.getEvent(id);
      expect(row!.isOwn, equals(1));

      // Signature verifies against the owner's public key over decoded id bytes.
      final idBytes = crockfordBase32Decode(stored.id);
      expect(crypto.verify(f.ownPublicKey, idBytes, stored.sig), isTrue);
    });

    test('empty caption is valid', () async {
      final f = await buildFixture();
      final id = await f.service.createPost(
        photoBytes: Uint8List.fromList([1, 2, 3]),
        caption: '',
      );
      final stored = await f.storage.getEvent(id);
      expect(stored!.content, isEmpty);
    });

    test('two posts with identical inputs but advancing clock produce '
        'different ids', () async {
      final f = await buildFixture();
      final photo = Uint8List.fromList([1, 2, 3]);
      final id1 = await f.service.createPost(photoBytes: photo, caption: 'a');
      f.clock.value += 1;
      final id2 = await f.service.createPost(photoBytes: photo, caption: 'a');
      expect(id1, isNot(equals(id2)));
    });

    test('throws if identity is null', () async {
      final f = await buildFixture();
      final service = DefaultPostService(
        contentKey: PairwiseContentKeyService(
          crypto: crypto,
          cache: FeedKeyCache()..put(f.identity.pubkey, f.identity.feedKey, 0),
          ownPubkey: f.identity.pubkey,
          ownSecretKey: Uint8List(64),
        ),
        crypto: crypto,
        storage: f.storage,
        media: f.media,
        clock: f.clock,
        identityLookup: () async => null,
      );
      expect(
        () => service.createPost(
          photoBytes: Uint8List(1),
          caption: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('deletePost', () {
    test('creates a kind=6 event referencing the target id', () async {
      final f = await buildFixture();
      final targetId = await f.service.createPost(
        photoBytes: Uint8List.fromList([7, 8, 9]),
        caption: 'to be deleted',
      );
      f.clock.value += 1;
      final deleteId = await f.service.deletePost(targetId);

      final deleteEvent = await f.storage.getEvent(deleteId);
      expect(deleteEvent, isNotNull);
      expect(deleteEvent!.kind, equals(EventKind.delete));
      expect(deleteEvent.ref, equals(targetId));
      expect(deleteEvent.content, isEmpty);
      expect(deleteEvent.media, isEmpty);

      // Target event still exists in storage; filtering is a feed-query concern.
      final target = await f.storage.getEvent(targetId);
      expect(target, isNotNull);
    });
  });
}

class _Fixture {
  _Fixture({
    required this.db,
    required this.storage,
    required this.crypto,
    required this.service,
    required this.media,
    required this.clock,
    required this.identity,
    required this.ownPublicKey,
  });

  final AppDatabase db;
  final StorageService storage;
  final CryptoService crypto;
  final PostService service;
  final _StubMediaService media;
  final _FixedClock clock;
  final Identity identity;
  final Uint8List ownPublicKey;
}
