import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starling/providers/identity_provider.dart';
import 'package:starling/providers/onboarding_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/router.dart';
import 'package:starling/screens/feed/feed_screen.dart';
import 'package:starling/screens/onboarding/done_screen.dart';
import 'package:starling/screens/onboarding/recovery_phrase_screen.dart';
import 'package:starling/screens/onboarding/setup_screen.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/theme/starling_theme.dart';

/// In-memory storage with a pre-seeded identity, so the router's identity gate
/// treats the user as already onboarded (`hasIdentity == true`).
Future<ProviderContainer> _buildContainer() async {
  final db = AppDatabase.memory();
  await db.identityDao.upsertIdentity(
    IdentityEntriesCompanion.insert(
      pubkey: 'pk',
      feedKey: Uint8List(32),
      recoveryPhrase: const Value(null),
      createdAt: 0,
    ),
  );
  final storage = DriftStorageService(db, const SystemClock());
  final container = ProviderContainer(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
  );
  addTearDown(() {
    container.dispose();
    db.close();
  });
  return container;
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final routerProvider = Provider((ref) => buildRouter(ref));
  final router = container.read(routerProvider);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildStarlingMaterialTheme(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('/onboarding/done renders for an onboarded user (not bounced)', (
    tester,
  ) async {
    final container = await _buildContainer();
    final router = await _pumpRouter(tester, container);

    // The identity exists (post-signup), yet the capstone must show instead of
    // being redirected to /feed like every other onboarding route.
    router.go('/onboarding/done');
    await tester.pumpAndSettle();

    expect(find.byType(DoneScreen), findsOneWidget);
  });

  testWidgets('other /onboarding routes still bounce to feed once onboarded', (
    tester,
  ) async {
    final container = await _buildContainer();
    final router = await _pumpRouter(tester, container);

    router.go('/onboarding/setup');
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
  });

  testWidgets(
    'recovery screen survives the post-create identity reload (no bounce)',
    (tester) async {
      final container = await _buildContainer();
      // The phrase createIdentity() would have cached — without it the screen
      // itself bails back to welcome.
      container
          .read(onboardingControllerProvider.notifier)
          .debugSeedPhrase(List.filled(24, 'starling'));
      final router = await _pumpRouter(tester, container);

      router.go('/onboarding/recovery');
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryPhraseScreen), findsOneWidget);

      // The race: createIdentity() invalidates the identity provider before
      // setup navigates here; when the async reload lands, _IdentityRefresh
      // re-runs the redirect. The recovery exemption must hold the route.
      container.read(identityControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byType(RecoveryPhraseScreen), findsOneWidget);
      expect(find.byType(FeedScreen), findsNothing);
    },
  );
}
