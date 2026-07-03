import 'package:flutter_test/flutter_test.dart';
import 'package:starling/services/storage/database.dart';

/// Plan 17 schema (v8 → v9): the three chatroom tables and the typed
/// outbound-queue column. A fresh in-memory DB runs `onCreate`/`createAll`
/// over the same table definitions the `from < 9` migration creates.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  test('schemaVersion is 13', () {
    // v9 added the Plan 17 chatroom tables; v10 dropped the vestigial follow
    // name/avatar columns; v11 added the voice-room missed-call flag; v12
    // added the paired-relay prune horizon (deletion & retention); v13
    // added the relay health columns (A7) + fan-out heal markers (A2/A3).
    expect(db.schemaVersion, 13);
  });

  test('v13: paired_relay health columns + relay_fanout_state table exist',
      () async {
    final cols = await db
        .customSelect("PRAGMA table_info('paired_relay_entries')")
        .get();
    final byName = {for (final c in cols) c.data['name'] as String: c.data};
    expect(byName.containsKey('last_push_at'), isTrue);
    expect(byName.containsKey('last_error'), isTrue);
    expect(byName['last_error']!['notnull'], 0, reason: 'nullable');

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name = 'relay_fanout_state_entries'",
        )
        .get();
    expect(tables, hasLength(1));
  });

  test('the three chatroom tables exist', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((r) => r.data['name'] as String).toSet();
    expect(
      names,
      containsAll([
        'room_entries',
        'room_member_entries',
        'room_key_history_entries',
      ]),
    );
  });

  test('outbound_queue_entries gains a nullable item_type column', () async {
    final cols = await db
        .customSelect("PRAGMA table_info('outbound_queue_entries')")
        .get();
    final byName = {for (final c in cols) c.data['name'] as String: c.data};
    expect(byName.containsKey('item_type'), isTrue);
    // Nullable ⇒ notnull flag is 0 (pre-Plan-17 rows read back as null/'event').
    expect(byName['item_type']!['notnull'], 0);
  });
}
