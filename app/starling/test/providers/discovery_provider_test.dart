import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/providers/discovery_provider.dart';
import 'package:starling/providers/identity_provider.dart';
import 'package:starling/providers/server_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/mocks/mock_mdns_service.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.value);
  final int value;
  @override
  int nowUnixSeconds() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers mDNS once identity + server port are ready', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const clock = _FixedClock(1000);
    final storage = DriftStorageService(db, clock);

    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'alice-pk',
        feedKey: Uint8List(32),
        recoveryPhrase: const Value(null),
        createdAt: 1000,
      ),
    );

    final mdns = MockMdnsService();
    addTearDown(mdns.dispose);

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        mdnsServiceProvider.overrideWithValue(mdns),
        // Fake the server port directly so we don't need a real shelf bind.
        httpServerControllerProvider.overrideWith(_StubHttpServer.new),
      ],
    );
    addTearDown(container.dispose);

    // Wait for identity + server-port to settle.
    await container.read(identityControllerProvider.future);
    await container.read(httpServerControllerProvider.future);
    await container.read(discoveryControllerProvider.future);

    expect(mdns.isRegistered, isTrue);
    expect(mdns.lastPubkey, equals('alice-pk'));
    expect(mdns.lastPort, equals(49000));
  });

  test('peer cache emits new state when a peer is discovered', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const clock = _FixedClock(1000);
    final storage = DriftStorageService(db, clock);
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'alice-pk',
        feedKey: Uint8List(32),
        recoveryPhrase: const Value(null),
        createdAt: 1000,
      ),
    );

    final mdns = MockMdnsService();
    addTearDown(mdns.dispose);

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        mdnsServiceProvider.overrideWithValue(mdns),
        httpServerControllerProvider.overrideWith(_StubHttpServer.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(identityControllerProvider.future);
    await container.read(httpServerControllerProvider.future);

    // Keep a live subscription so the auto-dispose provider doesn't
    // tear down between reads.
    final sub = container.listen(discoveryControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(discoveryControllerProvider.future);

    mdns.setPeer(
      const LanPeer(pubkey: 'bob-pk', host: '10.0.0.5', port: 49001),
    );

    await pumpEventQueue();
    final state = container.read(discoveryControllerProvider).value ?? const {};
    expect(state, contains('bob-pk'));
  });

  test('deregisters mDNS when the container disposes', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    const clock = _FixedClock(1000);
    final storage = DriftStorageService(db, clock);
    await db.identityDao.upsertIdentity(
      IdentityEntriesCompanion.insert(
        pubkey: 'alice-pk',
        feedKey: Uint8List(32),
        recoveryPhrase: const Value(null),
        createdAt: 1000,
      ),
    );

    final mdns = MockMdnsService();
    addTearDown(mdns.dispose);

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        mdnsServiceProvider.overrideWithValue(mdns),
        httpServerControllerProvider.overrideWith(_StubHttpServer.new),
      ],
    );
    await container.read(identityControllerProvider.future);
    await container.read(httpServerControllerProvider.future);
    final sub = container.listen(discoveryControllerProvider, (_, _) {});
    await container.read(discoveryControllerProvider.future);

    expect(mdns.isRegistered, isTrue);
    sub.close();
    container.dispose();

    // Allow the dispose callback's deregister Future to run.
    await pumpEventQueue();
    expect(mdns.isRegistered, isFalse);
  });
}

/// Stand-in for the real `HttpServerController` that just publishes a
/// fixed port. Avoids spinning up a real shelf server in unit tests.
class _StubHttpServer extends HttpServerController {
  @override
  Future<int?> build() async => 49000;
}
