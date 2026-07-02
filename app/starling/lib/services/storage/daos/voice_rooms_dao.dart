import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/voice_room_participants_table.dart';
import '../tables/voice_rooms_table.dart';

part 'voice_rooms_dao.g.dart';

/// Local-only voice-room history (Plan 16). No feed events involved; rows are
/// purely for the "recent rooms" UI and are pruned after 7 days.
@DriftAccessor(tables: [VoiceRoomEntries, VoiceRoomParticipantEntries])
class VoiceRoomsDao extends DatabaseAccessor<AppDatabase>
    with _$VoiceRoomsDaoMixin {
  VoiceRoomsDao(super.db);

  Future<void> upsertRoom(VoiceRoomEntriesCompanion entry) =>
      into(voiceRoomEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> setRoomEnded(String id, int endedAt) =>
      (update(voiceRoomEntries)..where((r) => r.id.equals(id))).write(
        VoiceRoomEntriesCompanion(endedAt: Value(endedAt)),
      );

  Future<void> upsertParticipant(VoiceRoomParticipantEntriesCompanion entry) =>
      into(
        voiceRoomParticipantEntries,
      ).insert(entry, mode: InsertMode.insertOrReplace);

  Future<List<VoiceRoomEntry>> recentRooms(int limit) =>
      (select(voiceRoomEntries)
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
            ..limit(limit))
          .get();

  /// Live view of [recentRooms] — re-emits on any voice_rooms write, so a
  /// just-finished (or just-missed) call appears without an app restart.
  Stream<List<VoiceRoomEntry>> watchRecentRooms(int limit) =>
      (select(voiceRoomEntries)
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
            ..limit(limit))
          .watch();

  Future<List<VoiceRoomParticipantEntry>> participantsFor(String roomId) =>
      (select(voiceRoomParticipantEntries)
            ..where((p) => p.roomId.equals(roomId))
            ..orderBy([(p) => OrderingTerm.asc(p.joinedAt)]))
          .get();

  /// Delete rooms (and their participants) created before [cutoff]. Returns
  /// the number of rooms removed.
  Future<int> evictOlderThan(int cutoff) async {
    final stale = await (select(
      voiceRoomEntries,
    )..where((r) => r.createdAt.isSmallerThanValue(cutoff))).get();
    if (stale.isEmpty) return 0;
    final ids = stale.map((r) => r.id).toList();
    await (delete(
      voiceRoomParticipantEntries,
    )..where((p) => p.roomId.isIn(ids))).go();
    await (delete(
      voiceRoomEntries,
    )..where((r) => r.createdAt.isSmallerThanValue(cutoff))).go();
    return stale.length;
  }
}
