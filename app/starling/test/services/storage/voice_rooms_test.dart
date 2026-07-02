import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/voice_room.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';

void main() {
  late AppDatabase db;
  late DriftStorageService storage;

  int nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    db = AppDatabase.memory();
    storage = DriftStorageService(db, const SystemClock());
  });

  tearDown(() async => db.close());

  test('round-trips a room with participants, newest first', () async {
    final now = nowSecs();
    await storage.saveVoiceRoom(
      VoiceRoom(
        id: 'r1',
        name: 'Morning call',
        creatorPubkey: 'ALICE',
        createdAt: now - 100,
      ),
    );
    await storage.saveVoiceRoomParticipant('r1', 'ALICE', joinedAt: now - 100);
    await storage.saveVoiceRoomParticipant(
      'r1',
      'BOB',
      displayName: 'Bob',
      joinedAt: now - 90,
    );

    await storage.saveVoiceRoom(
      VoiceRoom(
        id: 'r2',
        name: 'Later call',
        creatorPubkey: 'ALICE',
        createdAt: now,
      ),
    );

    final rooms = await storage.getRecentVoiceRooms(limit: 10);
    expect(rooms.map((r) => r.id), ['r2', 'r1'], reason: 'newest first');

    final r1 = rooms.firstWhere((r) => r.id == 'r1');
    expect(r1.name, 'Morning call');
    expect(r1.participants.map((p) => p.pubkey), containsAll(['ALICE', 'BOB']));
    expect(
      r1.participants.firstWhere((p) => p.pubkey == 'BOB').displayName,
      'Bob',
    );
  });

  test('updateVoiceRoomEnded stamps the end time', () async {
    final now = nowSecs();
    await storage.saveVoiceRoom(
      VoiceRoom(id: 'r1', name: 'Call', creatorPubkey: 'ALICE', createdAt: now),
    );
    await storage.updateVoiceRoomEnded('r1', now + 60);

    final room = (await storage.getRecentVoiceRooms()).single;
    expect(room.endedAt, now + 60);
    expect(room.isActive, isFalse);
  });

  test(
    'evictOldVoiceRooms prunes rooms past the age cap, keeps recent',
    () async {
      final now = nowSecs();
      const week = 7 * 24 * 60 * 60;
      await storage.saveVoiceRoom(
        VoiceRoom(
          id: 'old',
          name: 'Old',
          creatorPubkey: 'A',
          createdAt: now - week - 3600,
        ),
      );
      await storage.saveVoiceRoomParticipant('old', 'A', joinedAt: now - week);
      await storage.saveVoiceRoom(
        VoiceRoom(
          id: 'fresh',
          name: 'Fresh',
          creatorPubkey: 'A',
          createdAt: now - 3600,
        ),
      );

      final removed = await storage.evictOldVoiceRooms(week);
      expect(removed, 1);

      final rooms = await storage.getRecentVoiceRooms();
      expect(rooms.map((r) => r.id), ['fresh']);

      // Participants of the evicted room are gone too.
      final freshParts = rooms.single.participants;
      expect(freshParts, isEmpty);
    },
  );
}
