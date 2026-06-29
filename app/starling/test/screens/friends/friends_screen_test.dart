import 'dart:typed_data';

import 'package:starling/models/connection_card.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/profile_content.dart';
import 'package:starling/providers/server_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/screens/friends/friends_screen.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/qr_invite_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _harness(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/friends',
    routes: [
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(
        path: '/friends/scan',
        builder: (_, _) => const Scaffold(body: Text('scan stub')),
      ),
      GoRoute(
        path: '/friends/profile/:pubkey',
        builder: (_, _) => const Scaffold(body: Text('profile stub')),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      theme: buildStarlingMaterialTheme(),
    ),
  );
}

Future<ProviderContainer> _container({
  required MockStorageService storage,
  bool seedOnion = false,
}) async {
  await SodiumCryptoService.init();
  final container = ProviderContainer(overrides: [
    storageServiceProvider.overrideWithValue(storage),
    httpServerControllerProvider.overrideWith(
      () => _StubServerController(),
    ),
  ]);
  if (seedOnion) {
    // Tests that open the QR sheet need the onion address populated;
    // otherwise `QrInviteSheet` renders its "Connecting to Tor…" loader
    // and the `CircularProgressIndicator`'s infinite animation prevents
    // `pumpAndSettle` from ever settling.
    container
        .read(onionAddressProvider.notifier)
        .set('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.onion');
  }
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state renders the Add a friend card + helper text',
      (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 1))),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    final container = await _container(storage: storage);
    // LIFO: dispose the container (cancelling its stream subscriptions)
    // before storage closes the controllers they listen to.
    addTearDown(storage.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Add a friend'), findsOneWidget);
    expect(find.text('No friends yet'), findsOneWidget);
  });

  testWidgets('inbound request banner renders Accept / Reject',
      (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 2))),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    await storage.saveInboundRequest(FollowRequest(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 3))),
      payload: Uint8List(0),
      createdAt: 1000,
      requestTimestamp: 990,
    ));
    final container = await _container(storage: storage);
    // LIFO: dispose the container (cancelling its stream subscriptions)
    // before storage closes the controllers they listen to.
    addTearDown(storage.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('wants to follow you'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('tap + icon opens the QrInviteSheet',
      (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 4))),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    final container = await _container(storage: storage, seedOnion: true);
    // LIFO: dispose the container (cancelling its stream subscriptions)
    // before storage closes the controllers they listen to.
    addTearDown(storage.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();

    expect(find.byType(QrInviteSheet), findsOneWidget);
    expect(find.text('Scan to add me as a friend'), findsOneWidget);
  });

  testWidgets('tap Add a friend card also opens QrInviteSheet',
      (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 5))),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    final container = await _container(storage: storage, seedOnion: true);
    // LIFO: dispose the container (cancelling its stream subscriptions)
    // before storage closes the controllers they listen to.
    addTearDown(storage.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(QrInviteSheet), findsOneWidget);
  });

  testWidgets('friend rows render reachable / last-seen status',
      (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 6))),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    final friendCard = ConnectionCard(
      pubkey: crockfordBase32Encode(Uint8List.fromList(List.filled(32, 7))),
    );
    await storage.saveFollow(Follow(
      pubkey: friendCard.pubkey,
      connectionCard: friendCard.toMap().toString(),
      feedKey: Uint8List(32),
      lastSyncedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 5,
    ));
    // The friend's name now resolves from their latest kind=2 profile event
    // (the follows row carries no live name), so seed one.
    await storage.saveEvent(Event(
      version: '2026-04-28',
      id: 'profile-alex',
      pubkey: friendCard.pubkey,
      createdAt: 500,
      kind: EventKind.profile,
      ref: null,
      content: encodeProfileContent(name: 'Alex'),
      media: const [],
      sig: Uint8List(64),
      msgSeq: null,
    ));
    final container = await _container(storage: storage);
    // LIFO: dispose the container (cancelling its stream subscriptions)
    // before storage closes the controllers they listen to.
    addTearDown(storage.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('● Reachable'), findsOneWidget);
  });
}

class _StubServerController extends HttpServerController {
  @override
  Future<int?> build() async => 12345;
}
