import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/profile_content.dart';
import 'package:starling/providers/follow_profile_provider.dart';
import 'package:starling/providers/own_profile_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/storage_service.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final int value;
  @override
  int nowUnixSeconds() => value;
}

Event _profileEvent({
  required String id,
  required String pubkey,
  required int createdAt,
  required String name,
  String? avatarHash,
  int? msgSeq,
}) =>
    Event(
      version: '2026-04-28',
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: EventKind.profile,
      ref: null,
      content: encodeProfileContent(name: name, avatarHash: avatarHash),
      media: const [],
      sig: Uint8List(64),
      msgSeq: msgSeq,
    );

Future<DriftStorageService> _storageWithIdentity(AppDatabase db) async {
  final storage = DriftStorageService(db, const _FixedClock(1000));
  await db.identityDao.upsertIdentity(IdentityEntriesCompanion.insert(
    pubkey: 'me',
    feedKey: Uint8List(32),
    recoveryPhrase: const Value(null),
    createdAt: 1000,
  ));
  return storage;
}

ProviderContainer _container(StorageService storage) {
  final c = ProviderContainer(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ownProfile reads the latest kind=2 by created_at (with msg_seq)',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final storage = await _storageWithIdentity(db);
    await storage
        .saveEvent(_profileEvent(id: 'p1', pubkey: 'me', createdAt: 100, name: 'Old'));
    await storage.saveEvent(_profileEvent(
        id: 'p2', pubkey: 'me', createdAt: 200, name: 'New', avatarHash: 'h', msgSeq: 5));

    final snap = await _container(storage).read(ownProfileProvider.future);
    expect(snap.displayName, 'New');
    expect(snap.avatarHash, 'h');
    expect(snap.avatarMsgSeq, 5);
  });

  test('ownProfile falls back to "You" when no kind=2 exists', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final storage = await _storageWithIdentity(db);

    final snap = await _container(storage).read(ownProfileProvider.future);
    expect(snap.displayName, 'You');
    expect(snap.avatarHash, isNull);
  });

  test("followProfile reads a friend's latest kind=2", () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final storage = await _storageWithIdentity(db);
    await storage.saveEvent(_profileEvent(
        id: 'b1', pubkey: 'bob', createdAt: 300, name: 'Bob', avatarHash: 'bh', msgSeq: 2));

    final snap =
        await _container(storage).read(followProfileProvider('bob').future);
    expect(snap.displayName, 'Bob');
    expect(snap.avatarHash, 'bh');
    expect(snap.avatarMsgSeq, 2);
  });

  test('followProfile falls back to a short hash when friend has no kind=2',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final storage = await _storageWithIdentity(db);

    final snap = await _container(storage)
        .read(followProfileProvider('bobpubkey00001234').future);
    expect(snap.displayName, contains('…'));
    expect(snap.avatarHash, isNull);
  });
}
