import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/media_cache_table.dart';

part 'media_cache_dao.g.dart';

@DriftAccessor(tables: [MediaCacheEntries])
class MediaCacheDao extends DatabaseAccessor<AppDatabase>
    with _$MediaCacheDaoMixin {
  MediaCacheDao(super.db);

  Future<MediaCacheEntry?> getMedia(String hash) => (select(
    mediaCacheEntries,
  )..where((m) => m.hash.equals(hash))).getSingleOrNull();

  Future<List<String>> getAllHashes() async {
    final rows = await (selectOnly(
      mediaCacheEntries,
    )..addColumns([mediaCacheEntries.hash])).get();
    return [for (final r in rows) r.read(mediaCacheEntries.hash)!];
  }

  Future<void> upsertMedia(MediaCacheEntriesCompanion entry) =>
      into(mediaCacheEntries).insertOnConflictUpdate(entry);

  Future<void> deleteMedia(String hash) =>
      (delete(mediaCacheEntries)..where((m) => m.hash.equals(hash))).go();

  Future<int> getTotalSize() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(size), 0) AS total FROM media_cache_entries',
    ).getSingle();
    return result.data['total'] as int;
  }

  Future<void> evictToSize(int targetSize) async {
    var totalSize = await getTotalSize();
    if (totalSize <= targetSize) return;

    final oldest = await (select(
      mediaCacheEntries,
    )..orderBy([(m) => OrderingTerm.asc(m.lastAccessed)])).get();

    for (final entry in oldest) {
      if (totalSize <= targetSize) break;
      await (delete(
        mediaCacheEntries,
      )..where((m) => m.hash.equals(entry.hash))).go();
      totalSize -= entry.size;
    }
  }

  Future<int> evictOverLimit(int maxBytes) async {
    var totalSize = await getTotalSize();
    if (totalSize <= maxBytes) return 0;

    final oldest = await (select(
      mediaCacheEntries,
    )..orderBy([(m) => OrderingTerm.asc(m.lastAccessed)])).get();

    var evicted = 0;
    for (final entry in oldest) {
      if (totalSize <= maxBytes) break;
      await (delete(
        mediaCacheEntries,
      )..where((m) => m.hash.equals(entry.hash))).go();
      totalSize -= entry.size;
      evicted++;
    }
    return evicted;
  }

  /// Returns the entries that were evicted (so the caller can delete the
  /// underlying files). Skips any hash in [pinned] — typically the union of
  /// hashes referenced by `is_saved=1` and `is_own=1` events. If the
  /// non-pinned remainder fits under [maxBytes] no eviction occurs.
  Future<List<MediaCacheEntry>> evictOverLimitExcluding(
    int maxBytes,
    Set<String> pinned,
  ) async {
    final all = await (select(
      mediaCacheEntries,
    )..orderBy([(m) => OrderingTerm.asc(m.lastAccessed)])).get();

    var totalSize = 0;
    for (final e in all) {
      totalSize += e.size;
    }
    if (totalSize <= maxBytes) return const [];

    final removed = <MediaCacheEntry>[];
    for (final entry in all) {
      if (totalSize <= maxBytes) break;
      if (pinned.contains(entry.hash)) continue;
      await (delete(
        mediaCacheEntries,
      )..where((m) => m.hash.equals(entry.hash))).go();
      totalSize -= entry.size;
      removed.add(entry);
    }
    return removed;
  }

  /// Deletes every media_cache row whose hash is not in [pinned] and returns
  /// the deleted entries. Used by Settings → Clear cache.
  Future<List<MediaCacheEntry>> deleteAllExcluding(Set<String> pinned) async {
    final all = await select(mediaCacheEntries).get();
    final removed = <MediaCacheEntry>[];
    for (final entry in all) {
      if (pinned.contains(entry.hash)) continue;
      await (delete(
        mediaCacheEntries,
      )..where((m) => m.hash.equals(entry.hash))).go();
      removed.add(entry);
    }
    return removed;
  }

  /// SUM(size) over rows whose hash is in [hashes]. 0 if [hashes] is empty.
  Future<int> getTotalSizeForHashes(Set<String> hashes) async {
    if (hashes.isEmpty) return 0;
    final rows = await (select(
      mediaCacheEntries,
    )..where((m) => m.hash.isIn(hashes))).get();
    var total = 0;
    for (final r in rows) {
      total += r.size;
    }
    return total;
  }
}
