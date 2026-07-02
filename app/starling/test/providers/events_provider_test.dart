import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/providers/events_provider.dart';
import 'package:starling/providers/identity_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final int value;
  @override
  int nowUnixSeconds() => value;
}

Event _makeEvent({
  required String pubkey,
  required String id,
  required int createdAt,
  int kind = 1,
}) => Event(
  version: kStarlingProtocolVersion,
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: EventKind.fromValue(kind),
  content: Uint8List.fromList([0]),
  sig: Uint8List.fromList(List.filled(64, 0xAA)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returns [] when there is no identity', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final storage = DriftStorageService(db, const _FixedClock(1));
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final events = await container.read(ownEventsProvider.future);
    expect(events, isEmpty);
  });

  test('returns only own events', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const clock = _FixedClock(1000);
    final storage = DriftStorageService(db, clock);
    const ownPubkey = 'abcdef';
    const otherPubkey = '012345';
    // Seed identity + two own events + one from someone else.
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: ownPubkey,
        feedKey: Uint8List(32),
        recoveryPhrase: const Value(null),
        createdAt: 1000,
      ),
    );
    await storage.saveEvent(
      _makeEvent(pubkey: ownPubkey, id: 'id1', createdAt: 1001),
    );
    await storage.saveEvent(
      _makeEvent(pubkey: ownPubkey, id: 'id2', createdAt: 1002),
    );
    await storage.saveEvent(
      _makeEvent(pubkey: otherPubkey, id: 'id3', createdAt: 1003),
    );

    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    // Wait for identity to resolve before reading ownEvents.
    await container.read(identityControllerProvider.future);
    final events = await container.read(ownEventsProvider.future);
    expect(events.map((e) => e.id).toList()..sort(), ['id1', 'id2']);
  });
}
