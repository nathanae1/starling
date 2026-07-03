import 'package:drift/drift.dart';

/// Phone-side singleton recording the Relay the Owner has paired with.
///
/// Written on successful `/pair` round-trip. `relayId` is the
/// Relay-returned stable identifier (`blake2b_256(owner_pubkey ||
/// relay_onion)`) — a re-pair against the same Relay re-uses the same
/// id; pairing a different Relay produces a new id. `relayOnion` is
/// what the phone dials for `POST /events` / `POST /media` and what it
/// inserts into its Connection card as an `Endpoint(type: 'relay')`.
///
/// `relayBackfillComplete` tracks whether the one-shot initial backfill
/// of own events + media to the Relay has finished. Set to 0 on pair,
/// flipped to 1 once the iterator drains.
///
/// `relayPruneBefore` is the persisted prune horizon (Phase 3
/// deletion/retention): own posts with `createdAt < relayPruneBefore`
/// have been deliberately aged off the relay to free cap space and must
/// not be re-pushed by the reconciler. Persisted BEFORE the deletes are
/// issued so a crash mid-prune re-derives the same pruned set instead of
/// re-pushing. 0 = nothing pruned.
///
/// `lastPushAt`/`lastError` are the relay-health signal (A7): the unix
/// time of the last verified-converged pass (or successful publish push)
/// and the most recent error string, cleared on success. Lets the UI
/// distinguish a relay that 507s/401s forever from one still backfilling.
class PairedRelayEntries extends Table {
  TextColumn get relayId => text()();
  TextColumn get relayOnion => text()();
  IntColumn get pairedAt => integer()();
  IntColumn get relayBackfillComplete =>
      integer().withDefault(const Constant(0))();
  IntColumn get relayPruneBefore => integer().withDefault(const Constant(0))();
  IntColumn get lastPushAt => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {relayId};
}
