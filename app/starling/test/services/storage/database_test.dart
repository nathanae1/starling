import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
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

  test('database creates successfully', () async {
    // Just accessing a table triggers schema creation.
    final identity = await db.identityDao.getIdentity();
    expect(identity, isNull);
  });

  test('all 7 tables exist', () async {
    final result = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final tableNames = result.map((r) => r.data['name'] as String).toSet();

    expect(
      tableNames,
      containsAll([
        'identity_entries',
        'follow_entries',
        'event_entries',
        'media_cache_entries',
        'inbound_follow_request_entries',
        'outbound_follow_request_entries',
        'outbound_queue_entries',
      ]),
    );
  });

  test('event indexes exist', () async {
    final result = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name LIKE 'idx_events_%'",
        )
        .get();
    final indexNames = result.map((r) => r.data['name'] as String).toSet();

    expect(
      indexNames,
      containsAll(['idx_events_feed', 'idx_events_pubkey', 'idx_events_ref']),
    );
  });

  test('follow_entries has no vestigial name/avatar columns', () async {
    final cols = await db
        .customSelect('PRAGMA table_info(follow_entries)')
        .get();
    final names = cols.map((r) => r.data['name'] as String).toSet();
    expect(names, isNot(contains('display_name')));
    expect(names, isNot(contains('avatar_hash')));
    // The columns that matter still exist.
    expect(names, containsAll(['pubkey', 'connection_card', 'feed_key']));
  });

  test('follow round-trips its remaining columns through the DAO', () async {
    await db.followsDao.upsertFollow(
      FollowEntriesCompanion.insert(
        pubkey: 'pk-1',
        connectionCard: '{"pubkey":"pk-1"}',
        feedKey: Uint8List.fromList(List.filled(32, 0x11)),
        feedKeyEpoch: const Value(3),
        status: const Value('active'),
      ),
    );

    final row = await db.followsDao.getFollow('pk-1');
    expect(row, isNotNull);
    expect(row!.pubkey, 'pk-1');
    expect(row.connectionCard, '{"pubkey":"pk-1"}');
    expect(row.feedKey, Uint8List.fromList(List.filled(32, 0x11)));
    expect(row.feedKeyEpoch, 3);
    expect(row.status, 'active');
  });
}
