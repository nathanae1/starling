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

  UnknownEnvelopeItemEntriesCompanion makeItem({
    required String type,
    required int receivedAt,
    String sourcePubkey = 'pk-source',
    String envelopeVersion = '2026-03-24',
  }) => UnknownEnvelopeItemEntriesCompanion.insert(
    sourcePubkey: sourcePubkey,
    envelopeVersion: envelopeVersion,
    type: type,
    payload: Uint8List.fromList(List.filled(8, 0xAB)),
    extensions: const Value(null),
    receivedAt: receivedAt,
  );

  test('insert and getByType round-trip', () async {
    await db.unknownItemsDao.insert(makeItem(type: 'commit', receivedAt: 100));
    await db.unknownItemsDao.insert(makeItem(type: 'commit', receivedAt: 200));
    await db.unknownItemsDao.insert(makeItem(type: 'receipt', receivedAt: 150));

    final commits = await db.unknownItemsDao.getByType('commit');
    expect(commits, hasLength(2));
    expect(commits.every((e) => e.type == 'commit'), isTrue);

    final receipts = await db.unknownItemsDao.getByType('receipt');
    expect(receipts, hasLength(1));
    expect(receipts.single.receivedAt, equals(150));

    final unknown = await db.unknownItemsDao.getByType('does-not-exist');
    expect(unknown, isEmpty);
  });

  test('deleteOlderThan only removes rows older than the cutoff', () async {
    await db.unknownItemsDao.insert(makeItem(type: 'a', receivedAt: 100));
    await db.unknownItemsDao.insert(makeItem(type: 'a', receivedAt: 200));
    await db.unknownItemsDao.insert(makeItem(type: 'a', receivedAt: 300));

    final removed = await db.unknownItemsDao.deleteOlderThan(250);
    expect(removed, equals(2));

    final remaining = await db.unknownItemsDao.getByType('a');
    expect(remaining, hasLength(1));
    expect(remaining.single.receivedAt, equals(300));
  });
}
