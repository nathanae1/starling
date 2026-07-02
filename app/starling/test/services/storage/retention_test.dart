import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:starling/services/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  EventEntriesCompanion makeEvent(
    String id, {
    int createdAt = 1000,
    bool isOwn = false,
    bool isSaved = false,
    int? lastViewed,
    String? mediaRefsJson,
  }) => EventEntriesCompanion.insert(
    id: id,
    pubkey: isOwn ? 'me' : 'other',
    createdAt: createdAt,
    kind: 1,
    content: Uint8List.fromList([1]),
    sig: Uint8List.fromList(List.filled(64, 0)),
    fetchedAt: createdAt,
    isOwn: Value(isOwn ? 1 : 0),
    isSaved: Value(isSaved ? 1 : 0),
    lastViewed: Value(lastViewed),
    mediaRefs: Value(mediaRefsJson),
  );

  group('evictOldEvents', () {
    test('evicts old non-own events', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final old = now - 60 * 60 * 24 * 60; // 60 days ago

      await db.eventsDao.upsertEvent(makeEvent('old-1', createdAt: old));
      await db.eventsDao.upsertEvent(makeEvent('recent', createdAt: now));

      // maxAge = 30 days, graceLastViewed = 7 days
      final evicted = await db.eventsDao.evictOldEvents(
        30 * 24 * 60 * 60,
        7 * 24 * 60 * 60,
        now: now,
      );

      expect(evicted, equals(1));
      expect(await db.eventsDao.getEvent('old-1'), isNull);
      expect(await db.eventsDao.getEvent('recent'), isNotNull);
    });

    test('never evicts own events regardless of age', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final old = now - 60 * 60 * 24 * 60; // 60 days ago

      await db.eventsDao.upsertEvent(
        makeEvent('own-old', createdAt: old, isOwn: true),
      );

      final evicted = await db.eventsDao.evictOldEvents(
        30 * 24 * 60 * 60,
        7 * 24 * 60 * 60,
        now: now,
      );

      expect(evicted, equals(0));
      expect(await db.eventsDao.getEvent('own-old'), isNotNull);
    });

    test('respects last_viewed grace period', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final old = now - 60 * 60 * 24 * 60; // 60 days ago
      final recentView = now - 60 * 60 * 24 * 2; // 2 days ago

      await db.eventsDao.upsertEvent(
        makeEvent('viewed-recently', createdAt: old, lastViewed: recentView),
      );
      await db.eventsDao.upsertEvent(makeEvent('not-viewed', createdAt: old));

      final evicted = await db.eventsDao.evictOldEvents(
        30 * 24 * 60 * 60,
        7 * 24 * 60 * 60,
        now: now,
      );

      expect(evicted, equals(1));
      expect(await db.eventsDao.getEvent('viewed-recently'), isNotNull);
      expect(await db.eventsDao.getEvent('not-viewed'), isNull);
    });
  });

  group('evictMediaOverLimit', () {
    test('evicts oldest media when over limit', () async {
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'oldest',
          path: '/oldest',
          size: 500,
          lastAccessed: 100,
        ),
      );
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'newest',
          path: '/newest',
          size: 500,
          lastAccessed: 200,
        ),
      );

      final evicted = await db.mediaCacheDao.evictOverLimit(600);
      expect(evicted, equals(1));
      expect(await db.mediaCacheDao.getMedia('oldest'), isNull);
      expect(await db.mediaCacheDao.getMedia('newest'), isNotNull);
    });

    test('does nothing when under limit', () async {
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'h1',
          path: '/h1',
          size: 100,
          lastAccessed: 100,
        ),
      );

      final evicted = await db.mediaCacheDao.evictOverLimit(1000);
      expect(evicted, equals(0));
    });

    test('skips pinned hashes when over limit', () async {
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'pinned',
          path: '/pinned',
          size: 700,
          lastAccessed: 100,
        ),
      );
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'old-other',
          path: '/old-other',
          size: 700,
          lastAccessed: 200,
        ),
      );
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'recent-other',
          path: '/recent-other',
          size: 700,
          lastAccessed: 300,
        ),
      );

      // Limit 800 against 2100 total ⇒ must evict ~1300; "pinned" is the
      // oldest by lastAccessed but should be skipped, so the next-oldest
      // non-pinned ("old-other") goes first, then "recent-other" if needed.
      final removed = await db.mediaCacheDao.evictOverLimitExcluding(800, {
        'pinned',
      });

      final removedHashes = removed.map((e) => e.hash).toSet();
      expect(removedHashes.contains('pinned'), isFalse);
      expect(removedHashes, contains('old-other'));
      expect(await db.mediaCacheDao.getMedia('pinned'), isNotNull);
    });

    test('deleteAllExcluding leaves pinned alone', () async {
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'keep',
          path: '/keep',
          size: 100,
          lastAccessed: 1,
        ),
      );
      await db.mediaCacheDao.upsertMedia(
        MediaCacheEntriesCompanion.insert(
          hash: 'drop',
          path: '/drop',
          size: 100,
          lastAccessed: 2,
        ),
      );
      final removed = await db.mediaCacheDao.deleteAllExcluding({'keep'});
      expect(removed.map((e) => e.hash).toList(), equals(['drop']));
      expect(await db.mediaCacheDao.getMedia('keep'), isNotNull);
      expect(await db.mediaCacheDao.getMedia('drop'), isNull);
    });
  });

  group('getPinnedMediaRefsJson', () {
    test(
      'returns rows where isSaved=1 or isOwn=1 and mediaRefs is set',
      () async {
        String mediaJson(String hash) => jsonEncode([
          {'hash': hash, 'plaintext_size': 1, 'mime': 'image/jpeg'},
        ]);

        await db.eventsDao.upsertEvent(
          makeEvent(
            'own-with-media',
            isOwn: true,
            mediaRefsJson: mediaJson('own-hash'),
          ),
        );
        await db.eventsDao.upsertEvent(
          makeEvent(
            'saved-with-media',
            isSaved: true,
            mediaRefsJson: mediaJson('saved-hash'),
          ),
        );
        await db.eventsDao.upsertEvent(
          makeEvent('random-with-media', mediaRefsJson: mediaJson('drop-hash')),
        );
        await db.eventsDao.upsertEvent(makeEvent('plain-text-only'));

        final pinned = await db.eventsDao.getPinnedMediaRefsJson();
        expect(pinned.length, equals(2));
      },
    );
  });
}
