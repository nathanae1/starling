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

  MediaCacheEntriesCompanion makeMedia(
    String hash, {
    int size = 1000,
    int lastAccessed = 1000,
  }) => MediaCacheEntriesCompanion.insert(
    hash: hash,
    path: '/media/$hash',
    size: size,
    lastAccessed: lastAccessed,
  );

  test('saves and retrieves media', () async {
    await db.mediaCacheDao.upsertMedia(makeMedia('h1'));
    final media = await db.mediaCacheDao.getMedia('h1');
    expect(media, isNotNull);
    expect(media!.hash, equals('h1'));
    expect(media.path, equals('/media/h1'));
  });

  test('returns null for nonexistent media', () async {
    expect(await db.mediaCacheDao.getMedia('nope'), isNull);
  });

  test('deletes media', () async {
    await db.mediaCacheDao.upsertMedia(makeMedia('h1'));
    await db.mediaCacheDao.deleteMedia('h1');
    expect(await db.mediaCacheDao.getMedia('h1'), isNull);
  });

  test('computes total size', () async {
    await db.mediaCacheDao.upsertMedia(makeMedia('h1', size: 500));
    await db.mediaCacheDao.upsertMedia(makeMedia('h2', size: 300));
    expect(await db.mediaCacheDao.getTotalSize(), equals(800));
  });

  test('evicts oldest by last_accessed until under target', () async {
    await db.mediaCacheDao.upsertMedia(
      makeMedia('oldest', size: 500, lastAccessed: 100),
    );
    await db.mediaCacheDao.upsertMedia(
      makeMedia('middle', size: 500, lastAccessed: 200),
    );
    await db.mediaCacheDao.upsertMedia(
      makeMedia('newest', size: 500, lastAccessed: 300),
    );

    // Total is 1500. Evict to 600 — should remove oldest and middle.
    await db.mediaCacheDao.evictToSize(600);

    expect(await db.mediaCacheDao.getMedia('oldest'), isNull);
    expect(await db.mediaCacheDao.getMedia('middle'), isNull);
    expect(await db.mediaCacheDao.getMedia('newest'), isNotNull);
    expect(await db.mediaCacheDao.getTotalSize(), equals(500));
  });

  test('evictOverLimit returns count', () async {
    await db.mediaCacheDao.upsertMedia(
      makeMedia('h1', size: 500, lastAccessed: 100),
    );
    await db.mediaCacheDao.upsertMedia(
      makeMedia('h2', size: 500, lastAccessed: 200),
    );

    final evicted = await db.mediaCacheDao.evictOverLimit(600);
    expect(evicted, equals(1));
    expect(await db.mediaCacheDao.getTotalSize(), equals(500));
  });
}
