import 'package:drift/drift.dart';

/// Local-only call history (Plan 16). Voice rooms are coordinated over the
/// signaling plane and never stored as feed events; this table exists solely
/// to render the "recent rooms" list. Rows are evicted after 7 days.
class VoiceRoomEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get creatorPubkey => text()();
  IntColumn get createdAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get participantCount =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
