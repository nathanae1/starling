
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:starling/services/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  FollowEntriesCompanion makeFollow(String pubkey, {String status = 'active'}) =>
      FollowEntriesCompanion.insert(
        pubkey: pubkey,
        connectionCard: '{"pubkey":"$pubkey","endpoints":[]}',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
        status: Value(status),
      );

  test('saves and retrieves follow', () async {
    await db.followsDao.upsertFollow(makeFollow('pk-1'));

    final follow = await db.followsDao.getFollow('pk-1');
    expect(follow, isNotNull);
    expect(follow!.pubkey, equals('pk-1'));
    expect(follow.status, equals('active'));
  });

  test('getActiveFollows filters by status', () async {
    await db.followsDao.upsertFollow(makeFollow('pk-1'));
    await db.followsDao.upsertFollow(makeFollow('pk-2', status: 'blocked'));

    final active = await db.followsDao.getActiveFollows();
    expect(active, hasLength(1));
    expect(active.first.pubkey, equals('pk-1'));
  });

  test('removes follow', () async {
    await db.followsDao.upsertFollow(makeFollow('pk-1'));
    await db.followsDao.removeFollow('pk-1');

    final follow = await db.followsDao.getFollow('pk-1');
    expect(follow, isNull);
  });

  test('updates last synced timestamp', () async {
    await db.followsDao.upsertFollow(makeFollow('pk-1'));
    await db.followsDao.updateLastSynced('pk-1', 9999);

    final follow = await db.followsDao.getFollow('pk-1');
    expect(follow!.lastSyncedAt, equals(9999));
  });
}
