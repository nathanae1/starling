// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rooms_dao.dart';

// ignore_for_file: type=lint
mixin _$RoomsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomEntriesTable get roomEntries => attachedDatabase.roomEntries;
  $RoomMemberEntriesTable get roomMemberEntries =>
      attachedDatabase.roomMemberEntries;
  $RoomKeyHistoryEntriesTable get roomKeyHistoryEntries =>
      attachedDatabase.roomKeyHistoryEntries;
  RoomsDaoManager get managers => RoomsDaoManager(this);
}

class RoomsDaoManager {
  final _$RoomsDaoMixin _db;
  RoomsDaoManager(this._db);
  $$RoomEntriesTableTableManager get roomEntries =>
      $$RoomEntriesTableTableManager(_db.attachedDatabase, _db.roomEntries);
  $$RoomMemberEntriesTableTableManager get roomMemberEntries =>
      $$RoomMemberEntriesTableTableManager(
        _db.attachedDatabase,
        _db.roomMemberEntries,
      );
  $$RoomKeyHistoryEntriesTableTableManager get roomKeyHistoryEntries =>
      $$RoomKeyHistoryEntriesTableTableManager(
        _db.attachedDatabase,
        _db.roomKeyHistoryEntries,
      );
}
