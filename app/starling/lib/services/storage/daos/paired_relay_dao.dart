import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/paired_relay_table.dart';
import '../tables/pending_card_distributions_table.dart';

part 'paired_relay_dao.g.dart';

/// Phone-side storage for Relay pairing + Connection card distribution
/// (Plan 15).
///
/// - `paired_relay_entries`: singleton record of the Relay this Owner
///   has paired with.
/// - `pending_card_distribution_entries`: per-Follower outbox of signed
///   Connection card updates piggybacked on `/manifest`. Mirrors the
///   `pending_key_distribution_entries` flow in [KeyRotationDao].
@DriftAccessor(tables: [PairedRelayEntries, PendingCardDistributionEntries])
class PairedRelayDao extends DatabaseAccessor<AppDatabase>
    with _$PairedRelayDaoMixin {
  PairedRelayDao(super.db);

  // --- paired_relay ---

  Future<PairedRelayEntry?> getPairedRelay() =>
      (select(pairedRelayEntries)..limit(1)).getSingleOrNull();

  Future<void> setPairedRelay({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
  }) async {
    await delete(pairedRelayEntries).go();
    await into(pairedRelayEntries).insert(
      PairedRelayEntriesCompanion.insert(
        relayId: relayId,
        relayOnion: relayOnion,
        pairedAt: pairedAt,
      ),
    );
  }

  Future<void> markBackfillComplete(String relayId) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        const PairedRelayEntriesCompanion(relayBackfillComplete: Value(1)),
      );

  Future<void> clearPairedRelay() => delete(pairedRelayEntries).go();

  // --- pending_card_distributions ---

  Future<void> queueCardDistribution(
    PendingCardDistributionEntriesCompanion entry,
  ) => into(
    pendingCardDistributionEntries,
  ).insert(entry, mode: InsertMode.insertOrReplace);

  /// Latest undelivered card update for [targetPubkey], or null.
  /// "Latest" because a Follower offline across multiple updates only
  /// needs the most recent card — older intermediate cards are skipped.
  Future<PendingCardDistributionEntry?> latestPendingCardFor(
    String targetPubkey,
  ) =>
      (select(pendingCardDistributionEntries)
            ..where(
              (p) =>
                  p.targetPubkey.equals(targetPubkey) & p.distributed.equals(0),
            )
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Mark every undelivered card distribution for [targetPubkey] with
  /// `createdAt <= upTo` as delivered. Idempotent.
  Future<void> markCardDistributionsDelivered(String targetPubkey, int upTo) =>
      (update(pendingCardDistributionEntries)..where(
            (p) =>
                p.targetPubkey.equals(targetPubkey) &
                p.createdAt.isSmallerOrEqualValue(upTo),
          ))
          .write(
            const PendingCardDistributionEntriesCompanion(
              distributed: Value(1),
            ),
          );

  /// Drop every card distribution row for [targetPubkey]. Used when a
  /// Follower is removed — any pending card for them shouldn't leak via
  /// a later sync attempt.
  Future<void> clearCardDistributionsFor(String targetPubkey) => (delete(
    pendingCardDistributionEntries,
  )..where((p) => p.targetPubkey.equals(targetPubkey))).go();
}
