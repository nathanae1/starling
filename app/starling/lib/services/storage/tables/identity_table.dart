import 'package:drift/drift.dart';

class IdentityEntries extends Table {
  TextColumn get pubkey => text()();
  BlobColumn get feedKey => blob()();
  IntColumn get feedKeyEpoch => integer().withDefault(const Constant(0))();
  // The unix-seconds timestamp at which `feedKey` became the current key.
  // Pre-Plan-13 identity rows backfill this to `createdAt` during the v7
  // migration. Used together with `feed_key_history` to resolve historical
  // keys for own content encrypted under a previous key.
  IntColumn get feedKeyValidFrom => integer().withDefault(const Constant(0))();
  // MegOLM-shaped per-message sequence counter. Bumped under PublishLock
  // for every event we publish; reset to 0 when `feedKey` rotates.
  // Combined with the current `feedKey` (chain root for this epoch) via
  // `deriveMsgKey` to produce per-message AEAD keys.
  IntColumn get msgSeqCounter => integer().withDefault(const Constant(0))();
  TextColumn get recoveryPhrase => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {pubkey};
}
