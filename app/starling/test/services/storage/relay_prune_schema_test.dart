import 'package:flutter_test/flutter_test.dart';
import 'package:starling/services/storage/database.dart';

/// Phase 3 deletion & retention schema (v11 → v12): the paired-relay
/// prune-horizon column, plus the v12 → v13 health columns layered on
/// top. A fresh in-memory DB runs `onCreate`/`createAll` over the same
/// table definition the migrations alter, and the `from < 12` / `from <
/// 13` steps are exercised directly against a v11-shaped table.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  test('paired_relay_entries has relay_prune_before, default 0', () async {
    final cols = await db
        .customSelect("PRAGMA table_info('paired_relay_entries')")
        .get();
    final byName = {for (final c in cols) c.data['name'] as String: c.data};
    expect(byName.containsKey('relay_prune_before'), isTrue);
    expect(byName['relay_prune_before']!['dflt_value'], '0');
  });

  test('the v11→v12→v13 steps add columns to an existing row, preserving it',
      () async {
    // Rebuild paired_relay_entries as it looked at v11 (no prune column),
    // seed a row, then run exactly the from<12 and from<13 column steps.
    await db.customStatement('DROP TABLE paired_relay_entries');
    await db.customStatement(
      'CREATE TABLE paired_relay_entries ('
      'relay_id TEXT NOT NULL, '
      'relay_onion TEXT NOT NULL, '
      'paired_at INTEGER NOT NULL, '
      'relay_backfill_complete INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (relay_id))',
    );
    await db.customStatement(
      'INSERT INTO paired_relay_entries '
      '(relay_id, relay_onion, paired_at, relay_backfill_complete) '
      "VALUES ('r1', 'x.onion:80', 1000, 1)",
    );

    final m = db.createMigrator();
    await m.addColumn(
      db.pairedRelayEntries,
      db.pairedRelayEntries.relayPruneBefore,
    );
    await m.addColumn(db.pairedRelayEntries, db.pairedRelayEntries.lastPushAt);
    await m.addColumn(db.pairedRelayEntries, db.pairedRelayEntries.lastError);

    final row = await db.pairedRelayDao.getPairedRelay();
    expect(row, isNotNull);
    expect(row!.relayId, 'r1');
    expect(row.relayBackfillComplete, 1, reason: 'existing data preserved');
    expect(row.relayPruneBefore, 0, reason: 'new column defaults to 0');
    expect(row.lastPushAt, 0);
    expect(row.lastError, isNull);

    // And the DAO can move the horizon on the migrated table.
    await db.pairedRelayDao.setRelayPruneBefore('r1', 4242);
    expect((await db.pairedRelayDao.getPairedRelay())!.relayPruneBefore, 4242);

    // Health writes work on the migrated table too (A7).
    await db.pairedRelayDao.recordRelayError('r1', 'cap full');
    expect((await db.pairedRelayDao.getPairedRelay())!.lastError, 'cap full');
    await db.pairedRelayDao.recordRelayPush('r1', 7777);
    final healed = (await db.pairedRelayDao.getPairedRelay())!;
    expect(healed.lastPushAt, 7777);
    expect(healed.lastError, isNull, reason: 'success clears the error');
  });
}
