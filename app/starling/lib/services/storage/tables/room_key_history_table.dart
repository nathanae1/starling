import 'package:drift/drift.dart';

/// Per-room archive of retired room keys (chain roots), mirroring
/// [FollowFeedKeyHistoryEntries]. A row is appended on rotation (member
/// removal) before the fresh key overwrites `RoomEntries.roomKey`, so
/// messages authored in the retired key's `[validFrom, validUntil)` window
/// stay decryptable. PK `(roomId, epoch)`.
class RoomKeyHistoryEntries extends Table {
  TextColumn get roomId => text()();
  IntColumn get epoch => integer()();
  BlobColumn get roomKey => blob()();
  IntColumn get validFrom => integer()();
  IntColumn get validUntil => integer()();

  @override
  Set<Column> get primaryKey => {roomId, epoch};
}
