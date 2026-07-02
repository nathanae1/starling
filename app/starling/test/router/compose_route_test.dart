import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:starling/providers/compose_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/router.dart';
import 'package:starling/screens/compose/compose_screen.dart';
import 'package:starling/screens/compose/preview_screen.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _tinyJpeg() {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 2; x++) {
      image.setPixelRgb(x, y, 100, 100, 100);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// A StorageService backed by an in-memory Drift DB with a pre-seeded
/// identity, so the router's identity-gate redirect stays off of the
/// onboarding flow.
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

void main() {
  testWidgets('pushing /compose/preview stacks both pages; popping returns '
      'to compose with provider state intact', (tester) async {
    final container = await _buildContainer();

    // Seed compose state as if the user selected a photo + typed a caption.
    container
        .read(composeControllerProvider.notifier)
        .debugSeedState(
          ComposeState(
            photoBytes: _tinyJpeg(),
            phase: ComposePhase.ready,
            caption: 'meadow',
          ),
        );

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

    // Starts on /feed (inside the shell).
    expect(find.byType(ComposeScreen), findsNothing);

    // Push /compose as a fullscreen modal.
    unawaited(router.push('/compose'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(
      container.read(composeControllerProvider).caption,
      'meadow',
      reason: 'caption should survive mounting ComposeScreen',
    );

    // Push /compose/preview.
    unawaited(router.push('/compose/preview'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(
      container.read(composeControllerProvider).caption,
      'meadow',
      reason: 'caption should survive mounting PreviewScreen',
    );

    // Pop preview → compose is visible, caption preserved.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsNothing);
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(
      container.read(composeControllerProvider).caption,
      'meadow',
      reason: 'caption should survive popping back to compose',
    );
  });
}
