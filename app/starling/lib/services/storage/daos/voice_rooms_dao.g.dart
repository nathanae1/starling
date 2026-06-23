// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_rooms_dao.dart';

// ignore_for_file: type=lint
mixin _$VoiceRoomsDaoMixin on DatabaseAccessor<AppDatabase> {
  $VoiceRoomEntriesTable get voiceRoomEntries =>
      attachedDatabase.voiceRoomEntries;
  $VoiceRoomParticipantEntriesTable get voiceRoomParticipantEntries =>
      attachedDatabase.voiceRoomParticipantEntries;
  VoiceRoomsDaoManager get managers => VoiceRoomsDaoManager(this);
}

class VoiceRoomsDaoManager {
  final _$VoiceRoomsDaoMixin _db;
  VoiceRoomsDaoManager(this._db);
  $$VoiceRoomEntriesTableTableManager get voiceRoomEntries =>
      $$VoiceRoomEntriesTableTableManager(
        _db.attachedDatabase,
        _db.voiceRoomEntries,
      );
  $$VoiceRoomParticipantEntriesTableTableManager
  get voiceRoomParticipantEntries =>
      $$VoiceRoomParticipantEntriesTableTableManager(
        _db.attachedDatabase,
        _db.voiceRoomParticipantEntries,
      );
}
