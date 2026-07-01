import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/room_key_history_table.dart';
import '../tables/room_members_table.dart';
import '../tables/rooms_table.dart';

part 'rooms_dao.g.dart';

/// Durable chatroom identity/keys/members (Plan 17). Room messages live in
/// `event_entries` (kinds 102/103); this accessor owns the room row, its
/// roster, and the retired-key archive.
@DriftAccessor(tables: [RoomEntries, RoomMemberEntries, RoomKeyHistoryEntries])
class RoomsDao extends DatabaseAccessor<AppDatabase> with _$RoomsDaoMixin {
  RoomsDao(super.db);

  Future<void> upsertRoom(RoomEntriesCompanion entry) =>
      into(roomEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<RoomEntry?> getRoom(String id) =>
      (select(roomEntries)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// All rooms, newest activity first. Callers filter `isMember`.
  Future<List<RoomEntry>> getRooms() =>
      (select(roomEntries)
            ..orderBy([(r) => OrderingTerm.desc(r.lastActivityAt)]))
          .get();

  Future<void> updateRoomActivity(String roomId, int timestamp) =>
      (update(roomEntries)..where((r) => r.id.equals(roomId))).write(
        RoomEntriesCompanion(lastActivityAt: Value(timestamp)),
      );

  Future<void> setRoomLastRead(String roomId, int timestamp) =>
      (update(roomEntries)..where((r) => r.id.equals(roomId))).write(
        RoomEntriesCompanion(lastReadAt: Value(timestamp)),
      );

  Future<void> upsertMember(RoomMemberEntriesCompanion entry) =>
      into(roomMemberEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> setMemberRemoved(String roomId, String pubkey, int removedAt) =>
      (update(roomMemberEntries)
            ..where((m) => m.roomId.equals(roomId) & m.pubkey.equals(pubkey)))
          .write(RoomMemberEntriesCompanion(removedAt: Value(removedAt)));

  Future<List<RoomMemberEntry>> getMembers(String roomId) =>
      (select(roomMemberEntries)..where((m) => m.roomId.equals(roomId))).get();

  Future<void> appendKeyHistory(RoomKeyHistoryEntriesCompanion entry) => into(
    roomKeyHistoryEntries,
  ).insert(entry, mode: InsertMode.insertOrReplace);

  Future<List<RoomKeyHistoryEntry>> getKeyHistory(String roomId) =>
      (select(roomKeyHistoryEntries)
            ..where((k) => k.roomId.equals(roomId))
            ..orderBy([(k) => OrderingTerm.asc(k.validFrom)]))
          .get();

  /// Delete LEFT rooms (`isMember = 0`) idle since before [cutoff], plus
  /// their members and key history. Never touches joined rooms. Returns the
  /// number of rooms removed.
  Future<int> evictInactiveRooms(int cutoff) async {
    final stale =
        await (select(roomEntries)..where(
              (r) =>
                  r.isMember.equals(0) &
                  r.lastActivityAt.isSmallerThanValue(cutoff),
            ))
            .get();
    if (stale.isEmpty) return 0;
    final ids = stale.map((r) => r.id).toList();
    await (delete(roomMemberEntries)..where((m) => m.roomId.isIn(ids))).go();
    await (delete(
      roomKeyHistoryEntries,
    )..where((k) => k.roomId.isIn(ids))).go();
    await (delete(roomEntries)..where((r) => r.id.isIn(ids))).go();
    return stale.length;
  }
}
