import 'package:drift/drift.dart';

class EventEntries extends Table {
  TextColumn get id => text()();
  TextColumn get pubkey => text()();
  IntColumn get createdAt => integer()();
  IntColumn get kind => integer()();
  TextColumn get refId => text().nullable()();
  BlobColumn get content => blob()();
  TextColumn get mediaRefs => text().nullable()();
  BlobColumn get sig => blob()();
  IntColumn get isOwn => integer().withDefault(const Constant(0))();
  IntColumn get isSaved => integer().withDefault(const Constant(0))();
  IntColumn get fetchedAt => integer()();
  IntColumn get lastViewed => integer().nullable()();
  TextColumn get version => text().withDefault(const Constant('2026-03-24'))();
  BlobColumn get extensions => blob().nullable()();
  // MegOLM-shaped per-message sequence number persisted at decrypt time.
  // Together with the publisher's chain root for this event's epoch, it
  // re-derives the AEAD key used by media references on this post —
  // letting media decrypt long after the original sync without
  // re-fetching the EncryptedEvent wrapper.
  IntColumn get msgSeq => integer().nullable()();
  // Wire-format EncryptedEvent bytes captured at author time. Set only on
  // own posts (is_own=1) authored after schema v2; null for pre-migration
  // rows and for events received from peers. GET /events serves these
  // verbatim so the original author-time msgSeq is preserved — which is
  // what media blobs on disk are encrypted under.
  BlobColumn get encryptedPayload => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
