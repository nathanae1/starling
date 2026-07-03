import 'package:drift/drift.dart';

/// Singleton crash-safety markers for relay pair/unpair side effects (A2,
/// A3). A separate table from `paired_relay_entries` because unpair DELETEs
/// that row — the pending work must survive the mutation it heals.
///
/// `pendingCardFanout` is set BEFORE pair/unpair mutates pairing state and
/// cleared only after the updated Connection card has been sealed + queued
/// for every follower. A crash (or a degenerate card refused by the seal
/// guard) leaves it set; the heal pass re-runs distribution.
///
/// `pendingUnpairOnion` records a relay that has not yet been told about
/// its unpair (`POST /unpair`). Set before the local row is cleared,
/// cleared once the relay answers (any HTTP response < 500 — including "I
/// don't know that route" from an old relay) or after
/// `unpairNotifyAttempts` exceeds the give-up cap.
class RelayFanoutStateEntries extends Table {
  /// Always 1 — a one-row table.
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get pendingCardFanout => integer().withDefault(const Constant(0))();
  TextColumn get pendingUnpairOnion => text().nullable()();
  IntColumn get unpairNotifyAttempts =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
