import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/feed_key_history_table.dart';
import '../tables/follow_feed_key_history_table.dart';
import '../tables/pending_key_distributions_table.dart';

part 'key_rotation_dao.g.dart';

/// Storage operations for feed key rotation:
/// - `feed_key_history_entries`: own retired keys with their `[validFrom,
///   validUntil)` window (Plan 13).
/// - `follow_feed_key_history_entries`: per-follow retired keys, populated
///   when a peer's rotation arrives via `/manifest`. Lets us decrypt
///   cached content from before the rotation.
/// - `pending_key_distribution_entries`: encrypted new-key payloads waiting
///   to be delivered to remaining followers via the `/manifest` response.
@DriftAccessor(
  tables: [
    FeedKeyHistoryEntries,
    FollowFeedKeyHistoryEntries,
    PendingKeyDistributionEntries,
  ],
)
class KeyRotationDao extends DatabaseAccessor<AppDatabase>
    with _$KeyRotationDaoMixin {
  KeyRotationDao(super.db);

  // --- feed_key_history ---

  /// Append a retired key. Caller supplies the half-open `[validFrom,
  /// validUntil)` window the key was active for.
  Future<void> appendFeedKeyHistory(FeedKeyHistoryEntriesCompanion entry) =>
      into(feedKeyHistoryEntries).insert(entry);

  /// Returns the retired key whose `[validFrom, validUntil)` contains
  /// [timestamp], or null if none. Useful for decrypting own content
  /// authored under a previous key.
  Future<FeedKeyHistoryEntry?> feedKeyAt(int timestamp) =>
      (select(feedKeyHistoryEntries)
            ..where(
              (h) =>
                  h.validFrom.isSmallerOrEqualValue(timestamp) &
                  h.validUntil.isBiggerThanValue(timestamp),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<List<FeedKeyHistoryEntry>> getFeedKeyHistory() => (select(
    feedKeyHistoryEntries,
  )..orderBy([(h) => OrderingTerm.asc(h.validFrom)])).get();

  // --- follow_feed_key_history ---

  /// Append a retired chain root for [followPubkey]. Caller supplies the
  /// `[validFrom, validUntil)` window the key was active.
  Future<void> appendFollowFeedKeyHistory(
    FollowFeedKeyHistoryEntriesCompanion entry,
  ) => into(followFeedKeyHistoryEntries).insert(entry);

  /// All retired chain roots for [followPubkey], oldest first.
  Future<List<FollowFeedKeyHistoryEntry>> getFollowFeedKeyHistory(
    String followPubkey,
  ) =>
      (select(followFeedKeyHistoryEntries)
            ..where((h) => h.followPubkey.equals(followPubkey))
            ..orderBy([(h) => OrderingTerm.asc(h.validFrom)]))
          .get();

  // --- pending_key_distributions ---

  Future<void> addPendingDistribution(
    PendingKeyDistributionEntriesCompanion entry,
  ) => into(
    pendingKeyDistributionEntries,
  ).insert(entry, mode: InsertMode.insertOrReplace);

  /// Latest undelivered distribution for [targetPubkey], or null.
  /// "Latest" because a follower offline across multiple rotations only
  /// needs the most recent key — the older intermediate keys are skipped.
  Future<PendingKeyDistributionEntry?> latestPendingFor(String targetPubkey) =>
      (select(pendingKeyDistributionEntries)
            ..where(
              (p) =>
                  p.targetPubkey.equals(targetPubkey) & p.distributed.equals(0),
            )
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<List<PendingKeyDistributionEntry>> getPendingDistributionsFor(
    String targetPubkey,
  ) =>
      (select(pendingKeyDistributionEntries)
            ..where(
              (p) =>
                  p.targetPubkey.equals(targetPubkey) & p.distributed.equals(0),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
          .get();

  /// Mark every undelivered distribution row for [targetPubkey] with
  /// `createdAt <= upTo` as `distributed=1`. Idempotent.
  Future<void> markDistributionsDelivered(String targetPubkey, int upTo) =>
      (update(pendingKeyDistributionEntries)..where(
            (p) =>
                p.targetPubkey.equals(targetPubkey) &
                p.createdAt.isSmallerOrEqualValue(upTo),
          ))
          .write(
            const PendingKeyDistributionEntriesCompanion(distributed: Value(1)),
          );

  /// Drop every distribution row for [targetPubkey] outright. Used when
  /// the follower is being removed: any pending key for them shouldn't
  /// leak via a later sync attempt.
  Future<void> clearPendingDistributionsFor(String targetPubkey) => (delete(
    pendingKeyDistributionEntries,
  )..where((p) => p.targetPubkey.equals(targetPubkey))).go();
}
