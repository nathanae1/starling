import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/follows_table.dart';

part 'follows_dao.g.dart';

@DriftAccessor(tables: [FollowEntries])
class FollowsDao extends DatabaseAccessor<AppDatabase> with _$FollowsDaoMixin {
  FollowsDao(super.db);

  Future<List<FollowEntry>> getActiveFollows() =>
      (select(followEntries)..where((f) => f.status.equals('active'))).get();

  Stream<List<FollowEntry>> watchActiveFollows() =>
      (select(followEntries)..where((f) => f.status.equals('active'))).watch();

  Future<FollowEntry?> getFollow(String pubkey) => (select(
    followEntries,
  )..where((f) => f.pubkey.equals(pubkey))).getSingleOrNull();

  Future<void> upsertFollow(FollowEntriesCompanion entry) =>
      into(followEntries).insertOnConflictUpdate(entry);

  Future<void> removeFollow(String pubkey) =>
      (delete(followEntries)..where((f) => f.pubkey.equals(pubkey))).go();

  Future<void> updateLastSynced(String pubkey, int timestamp) =>
      (update(followEntries)..where((f) => f.pubkey.equals(pubkey))).write(
        FollowEntriesCompanion(lastSyncedAt: Value(timestamp)),
      );

  Future<void> updateLastFullSynced(String pubkey, int timestamp) =>
      (update(followEntries)..where((f) => f.pubkey.equals(pubkey))).write(
        FollowEntriesCompanion(lastFullSyncAt: Value(timestamp)),
      );

  /// Stamps `last_decrypt_failure_at` for [pubkey]. Pass `null` to clear
  /// (used after a fresh feed-key rotation lands).
  Future<void> setLastDecryptFailureAt(String pubkey, int? timestamp) =>
      (update(followEntries)..where((f) => f.pubkey.equals(pubkey))).write(
        FollowEntriesCompanion(lastDecryptFailureAt: Value(timestamp)),
      );

  Future<void> clearLastDecryptFailureIfSet(String pubkey) =>
      (update(followEntries)..where(
            (f) => f.pubkey.equals(pubkey) & f.lastDecryptFailureAt.isNotNull(),
          ))
          .write(
            const FollowEntriesCompanion(lastDecryptFailureAt: Value(null)),
          );
}
