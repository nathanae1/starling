import 'package:drift/drift.dart';

/// Chatroom roster (Plan 17). PK `(roomId, pubkey)`. A row with
/// `removedAt == null` is a currently-active member; removal stamps
/// `removedAt` rather than deleting, so history stays attributable.
class RoomMemberEntries extends Table {
  TextColumn get roomId => text()();
  TextColumn get pubkey => text()();
  TextColumn get displayName => text().nullable()();
  IntColumn get addedAt => integer()();
  IntColumn get removedAt => integer().nullable()();
  TextColumn get role => text().withDefault(const Constant('member'))();

  @override
  Set<Column> get primaryKey => {roomId, pubkey};
}
