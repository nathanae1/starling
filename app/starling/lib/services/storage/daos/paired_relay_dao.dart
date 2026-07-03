import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/paired_relay_table.dart';
import '../tables/pending_card_distributions_table.dart';
import '../tables/relay_fanout_state_table.dart';

part 'paired_relay_dao.g.dart';

/// Phone-side storage for Relay pairing + Connection card distribution
/// (Plan 15).
///
/// - `paired_relay_entries`: singleton record of the Relay this Owner
///   has paired with.
/// - `relay_fanout_state_entries`: singleton crash-safety markers for the
///   pair/unpair side effects (card fan-out, wire unpair notify).
/// - `pending_card_distribution_entries`: per-Follower outbox of signed
///   Connection card updates piggybacked on `/manifest`. Mirrors the
///   `pending_key_distribution_entries` flow in [KeyRotationDao].
@DriftAccessor(
  tables: [
    PairedRelayEntries,
    PendingCardDistributionEntries,
    RelayFanoutStateEntries,
  ],
)
class PairedRelayDao extends DatabaseAccessor<AppDatabase>
    with _$PairedRelayDaoMixin {
  PairedRelayDao(super.db);

  // --- paired_relay ---

  Future<PairedRelayEntry?> getPairedRelay() =>
      (select(pairedRelayEntries)..limit(1)).getSingleOrNull();

  /// One transaction: a crash between the delete and the insert must not
  /// leave the phone with no relay row at all (A2).
  Future<void> setPairedRelay({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
  }) => transaction(() async {
    await delete(pairedRelayEntries).go();
    await into(pairedRelayEntries).insert(
      PairedRelayEntriesCompanion.insert(
        relayId: relayId,
        relayOnion: relayOnion,
        pairedAt: pairedAt,
      ),
    );
  });

  Future<void> markBackfillComplete(String relayId) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        const PairedRelayEntriesCompanion(relayBackfillComplete: Value(1)),
      );

  /// A5: a later pass that finds the relay diverged (rejected pushes,
  /// failed deletes) un-flips the flag so the UI reads "syncing" again.
  Future<void> clearBackfillComplete(String relayId) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        const PairedRelayEntriesCompanion(relayBackfillComplete: Value(0)),
      );

  /// A7: stamp a verified-successful push/reconcile and clear any error.
  Future<void> recordRelayPush(String relayId, int at) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        PairedRelayEntriesCompanion(
          lastPushAt: Value(at),
          lastError: const Value(null),
        ),
      );

  /// A7: persist the most recent relay failure for the settings screen.
  Future<void> recordRelayError(String relayId, String message) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        PairedRelayEntriesCompanion(lastError: Value(message)),
      );

  /// Persist the prune horizon. Written BEFORE the relay deletes are
  /// issued (crash-safe ordering — see the table doc).
  Future<void> setRelayPruneBefore(String relayId, int pruneBefore) =>
      (update(
        pairedRelayEntries,
      )..where((r) => r.relayId.equals(relayId))).write(
        PairedRelayEntriesCompanion(relayPruneBefore: Value(pruneBefore)),
      );

  Future<void> clearPairedRelay() => delete(pairedRelayEntries).go();

  // --- relay_fanout_state (A2/A3 heal markers) ---

  Future<RelayFanoutStateEntry?> getFanoutState() =>
      (select(relayFanoutStateEntries)..limit(1)).getSingleOrNull();

  /// Upsert one column set on the singleton row.
  Future<void> _writeFanoutState(RelayFanoutStateEntriesCompanion patch) =>
      transaction(() async {
        final updated = await (update(
          relayFanoutStateEntries,
        )..where((s) => s.id.equals(1))).write(patch);
        if (updated == 0) {
          await into(relayFanoutStateEntries).insert(
            patch.copyWith(id: const Value(1)),
            mode: InsertMode.insertOrReplace,
          );
        }
      });

  Future<void> setPendingCardFanout(bool pending) => _writeFanoutState(
    RelayFanoutStateEntriesCompanion(
      pendingCardFanout: Value(pending ? 1 : 0),
    ),
  );

  /// Record (or clear, with null) the relay onion still owed a
  /// `POST /unpair`. Setting or clearing resets the attempt counter.
  Future<void> setPendingUnpair(String? relayOnion) => _writeFanoutState(
    RelayFanoutStateEntriesCompanion(
      pendingUnpairOnion: Value(relayOnion),
      unpairNotifyAttempts: const Value(0),
    ),
  );

  Future<void> incrementUnpairNotifyAttempts() => customUpdate(
    'UPDATE relay_fanout_state_entries '
    'SET unpair_notify_attempts = unpair_notify_attempts + 1 WHERE id = 1',
    updates: {relayFanoutStateEntries},
  );

  /// The local unpair mutation as ONE transaction (A2/A3): set the card
  /// fan-out marker, record [relayOnion] as owed a `POST /unpair`, and
  /// delete the paired-relay row. Atomic so a crash can never leave the
  /// relay notified-but-still-paired or cleared-but-never-notified.
  Future<void> beginUnpair(String relayOnion) => transaction(() async {
    await _writeFanoutState(
      RelayFanoutStateEntriesCompanion(
        pendingCardFanout: const Value(1),
        pendingUnpairOnion: Value(relayOnion),
        unpairNotifyAttempts: const Value(0),
      ),
    );
    await delete(pairedRelayEntries).go();
  });

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
