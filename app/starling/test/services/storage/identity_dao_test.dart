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

  test('returns null when no identity exists', () async {
    final identity = await db.identityDao.getIdentity();
    expect(identity, isNull);
  });

  test('saves and retrieves identity', () async {
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'test-pk',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
        recoveryPhrase: const Value('word1 word2 word3'),
        createdAt: 1000,
      ),
    );

    final identity = await db.identityDao.getIdentity();
    expect(identity, isNotNull);
    expect(identity!.pubkey, equals('test-pk'));
    expect(identity.feedKey, hasLength(32));
    expect(identity.recoveryPhrase, equals('word1 word2 word3'));
    expect(identity.createdAt, equals(1000));
  });

  test('upserts identity (updates existing)', () async {
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'test-pk',
        feedKey: Uint8List.fromList(List.filled(32, 0xAA)),
        createdAt: 1000,
      ),
    );

    // Update feed key.
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'test-pk',
        feedKey: Uint8List.fromList(List.filled(32, 0xBB)),
        createdAt: 1000,
      ),
    );

    final identity = await db.identityDao.getIdentity();
    expect(identity!.feedKey[0], equals(0xBB));
  });
}
