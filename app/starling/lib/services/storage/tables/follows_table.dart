import 'package:drift/drift.dart';

class FollowEntries extends Table {
  TextColumn get pubkey => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarHash => text().nullable()();
  TextColumn get connectionCard => text()();
  BlobColumn get feedKey => blob()();
  IntColumn get feedKeyEpoch => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncedAt => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  // The `created_at` stamp on the most recent rotated feed key we've
  // received from this peer (Plan 13). Sent back to the peer as
  // `ack_rotation_at` on the next /manifest call so they can mark the
  // distribution row delivered. 0 means "no rotation received yet."
  IntColumn get lastReceivedRotationAt =>
      integer().withDefault(const Constant(0))();
  // The `created_at` stamp on the most recent Connection card update we've
  // accepted from this peer (Plan 15). Sent back as `card_seen_at` on the
  // next /manifest call so the peer can mark the card distribution row
  // delivered. 0 means "no card update received yet."
  IntColumn get lastReceivedCardAt =>
      integer().withDefault(const Constant(0))();
  // Unix-second timestamp of the most recent decrypt failure attributable
  // to this peer's stored feed key (event or media). Set when we observe
  // a stale-key signal, cleared when a fresh rotation lands. Drives the
  // "Key fresh / stale" tile in connection settings.
  IntColumn get lastDecryptFailureAt => integer().nullable()();
  // When the last FULL manifest diff (paged, no since-window) completed
  // for this peer (D1). The windowed cursor can't see events that arrived
  // at a store out of author-time order; a periodic full id-diff catches
  // them. 0 means "never" — the first sync runs full.
  IntColumn get lastFullSyncAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {pubkey};
}
