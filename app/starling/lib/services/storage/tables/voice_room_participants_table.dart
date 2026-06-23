import 'package:drift/drift.dart';

/// Participants seen in a local voice-room history row (Plan 16). Cascade on
/// room eviction is done explicitly in [VoiceRoomsDao] (SQLite FK enforcement
/// is not relied upon), so `roomId` is a plain column, not a FK reference.
class VoiceRoomParticipantEntries extends Table {
  TextColumn get roomId => text()();
  TextColumn get pubkey => text()();
  TextColumn get displayName => text().nullable()();
  IntColumn get joinedAt => integer()();
  IntColumn get leftAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {roomId, pubkey};
}
