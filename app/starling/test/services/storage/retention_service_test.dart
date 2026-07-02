import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:starling/services/clock.dart';
import 'package:starling/services/media/encrypted_media_paths.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/storage/retention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FixedClock implements Clock {
  _FixedClock(this._t);
  final int _t;
  @override
  int nowUnixSeconds() => _t;
}

void main() {
  late AppDatabase db;
  late DriftStorageService storage;
  late Directory tempRoot;
  const now = 2_000_000_000;

  setUp(() async {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, _FixedClock(now));
    tempRoot = await Directory.systemTemp.createTemp('starling-retention-');
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  String fakeHash(String seed) {
    final ch = seed.codeUnits.first;
    return List<int>.filled(64, ch).map((c) {
      final v = (c % 16);
      return v.toRadixString(16);
    }).join();
  }

  Future<void> writeBlob(String hash, int size) async {
    final file = await resolveMediaFile(tempRoot, hash);
    await file.writeAsBytes(Uint8List(size));
  }

  test(
    'retention pass evicts unpinned media + deletes files; pinned survive',
    () async {
      final pinnedHash = fakeHash('p');
      final orphanHash = fakeHash('o');
      final ownHash = fakeHash('w');

      await writeBlob(pinnedHash, 800);
      await writeBlob(orphanHash, 800);
      await writeBlob(ownHash, 800);

      Future<void> insertEvent({
        required String id,
        required String pubkey,
        required int isOwn,
        required int isSaved,
        required int createdAt,
        required String? mediaJson,
        int? lastViewed,
      }) => db.eventsDao.upsertEvent(
        EventEntriesCompanion.insert(
          id: id,
          pubkey: pubkey,
          createdAt: createdAt,
          kind: 1,
          content: Uint8List.fromList([1]),
          sig: Uint8List.fromList(List.filled(64, 0)),
          fetchedAt: createdAt,
          isOwn: Value(isOwn),
          isSaved: Value(isSaved),
          mediaRefs: Value(mediaJson),
          lastViewed: Value(lastViewed),
        ),
      );

      String mediaJson(String hash) => jsonEncode([
        {'hash': hash, 'plaintext_size': 800, 'mime': 'image/jpeg'},
      ]);

      // Saved foreign event referencing pinnedHash → pinned via is_saved.
      await insertEvent(
        id: 'saved-evt',
        pubkey: 'friend',
        isOwn: 0,
        isSaved: 1,
        createdAt: now - 1000,
        mediaJson: mediaJson(pinnedHash),
      );
      // Own event referencing ownHash → pinned via is_own.
      await insertEvent(
        id: 'own-evt',
        pubkey: 'me',
        isOwn: 1,
        isSaved: 0,
        createdAt: now - 1000,
        mediaJson: mediaJson(ownHash),
      );
      // No event references orphanHash → eligible for eviction.

      for (final hash in [pinnedHash, orphanHash, ownHash]) {
        await db.mediaCacheDao.upsertMedia(
          MediaCacheEntriesCompanion.insert(
            hash: hash,
            path: mediaRelativePath(hash),
            size: 800,
            lastAccessed: now - 100,
          ),
        );
      }

      final retention = RetentionService(
        storage: storage,
        mediaRoot: tempRoot,
        // Force eviction by using a tiny limit (≪ 3 × 800).
        policy: const RetentionPolicy(maxMediaBytes: 1000),
      );
      final result = await retention.run();

      expect(result.mediaEvicted, equals(1));
      expect(await storage.getMedia(pinnedHash), isNotNull);
      expect(await storage.getMedia(ownHash), isNotNull);
      expect(await storage.getMedia(orphanHash), isNull);

      final pinnedFile = File(
        p.join(tempRoot.path, mediaRelativePath(pinnedHash)),
      );
      final ownFile = File(p.join(tempRoot.path, mediaRelativePath(ownHash)));
      final orphanFile = File(
        p.join(tempRoot.path, mediaRelativePath(orphanHash)),
      );
      expect(pinnedFile.existsSync(), isTrue);
      expect(ownFile.existsSync(), isTrue);
      expect(orphanFile.existsSync(), isFalse);
    },
  );

  test(
    'retention pass evicts old foreign events but spares saved/own',
    () async {
      const old = now - 60 * 24 * 60 * 60;

      Future<void> insertEvent({
        required String id,
        required String pubkey,
        required int isOwn,
        required int isSaved,
        required int createdAt,
      }) => db.eventsDao.upsertEvent(
        EventEntriesCompanion.insert(
          id: id,
          pubkey: pubkey,
          createdAt: createdAt,
          kind: 1,
          content: Uint8List.fromList([1]),
          sig: Uint8List.fromList(List.filled(64, 0)),
          fetchedAt: createdAt,
          isOwn: Value(isOwn),
          isSaved: Value(isSaved),
        ),
      );

      await insertEvent(
        id: 'old-foreign',
        pubkey: 'friend',
        isOwn: 0,
        isSaved: 0,
        createdAt: old,
      );
      await insertEvent(
        id: 'old-saved',
        pubkey: 'friend',
        isOwn: 0,
        isSaved: 1,
        createdAt: old,
      );
      await insertEvent(
        id: 'old-own',
        pubkey: 'me',
        isOwn: 1,
        isSaved: 0,
        createdAt: old,
      );

      final retention = RetentionService(storage: storage, mediaRoot: tempRoot);
      final result = await retention.run();

      expect(result.eventsEvicted, equals(1));
      expect(await db.eventsDao.getEvent('old-foreign'), isNull);
      expect(await db.eventsDao.getEvent('old-saved'), isNotNull);
      expect(await db.eventsDao.getEvent('old-own'), isNotNull);
    },
  );

  test('getPinnedMediaHashes resolves saved + own media refs', () async {
    final hash = fakeHash('z');
    await db.eventsDao.upsertEvent(
      EventEntriesCompanion.insert(
        id: 'e',
        pubkey: 'me',
        createdAt: now,
        kind: 1,
        content: Uint8List.fromList([1]),
        sig: Uint8List.fromList(List.filled(64, 0)),
        fetchedAt: now,
        isOwn: const Value(1),
        mediaRefs: Value(
          jsonEncode([
            {'hash': hash, 'plaintext_size': 1, 'mime': 'image/jpeg'},
          ]),
        ),
      ),
    );

    final pinned = await storage.getPinnedMediaHashes();
    expect(pinned, contains(hash));
  });

  test('clearCachedMediaExcluding removes only non-pinned rows', () async {
    final keep = fakeHash('k');
    final drop = fakeHash('d');

    for (final hash in [keep, drop]) {
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: hash,
          path: mediaRelativePath(hash),
          size: 100,
          lastAccessed: now,
        ),
      );
    }
    final removed = await storage.clearCachedMediaExcluding({keep});
    expect(removed.map((e) => e.hash).toList(), equals([drop]));
    expect(await storage.getMedia(keep), isNotNull);
    expect(await storage.getMedia(drop), isNull);
  });
}
