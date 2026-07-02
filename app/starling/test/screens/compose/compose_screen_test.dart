import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:starling/providers/compose_provider.dart';
import 'package:starling/screens/compose/compose_screen.dart';
import 'package:starling/screens/compose/preview_screen.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

/// Build a fake shell at `/home` that lets us push `/compose` and `/compose/preview`
/// so `context.pop()` has somewhere to go.
Widget _app(ProviderContainer container) {
  final rootKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/compose',
        parentNavigatorKey: rootKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: ComposeScreen()),
        routes: [
          GoRoute(
            path: 'preview',
            parentNavigatorKey: rootKey,
            pageBuilder: (_, _) => const MaterialPage(child: PreviewScreen()),
          ),
        ],
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

Future<void> _openCompose(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(_app(container));
  await tester.pumpAndSettle();
  // Navigate to /compose programmatically so the back stack has /home at the
  // bottom — otherwise ✕ has nothing to pop.
  final ctx = tester.element(find.text('home'));
  unawaited(GoRouter.of(ctx).push('/compose'));
  await tester.pumpAndSettle();
}

PrimaryButton _nextButton(WidgetTester tester) => tester.widget(
  find.byWidgetPredicate((w) => w is PrimaryButton && w.label == 'Next'),
);

Uint8List _tinyJpeg() {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 2; x++) {
      image.setPixelRgb(x, y, 128, 128, 128);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  // Plan 05 forbids trust / encryption microcopy on Compose and Preview.
  test('no "end-to-end encrypted" microcopy in compose sources', () {
    const roots = [
      'lib/screens/compose/compose_screen.dart',
      'lib/screens/compose/preview_screen.dart',
    ];
    for (final path in roots) {
      final src = File(path).readAsStringSync().toLowerCase();
      expect(
        src.contains('end-to-end'),
        isFalse,
        reason: '$path must not mention end-to-end',
      );
      expect(
        src.contains('encrypt'),
        isFalse,
        reason: '$path must not mention encryption',
      );
    }
  });

  testWidgets('Next is disabled without a photo, enabled with one', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    expect(_nextButton(tester).onPressed, isNull);

    container
        .read(composeControllerProvider.notifier)
        .debugSeedState(
          ComposeState(photoBytes: _tinyJpeg(), phase: ComposePhase.ready),
        );
    await tester.pump();

    expect(_nextButton(tester).onPressed, isNotNull);
  });

  testWidgets('Cancel on a clean draft pops immediately (no confirm)', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    await tester.tap(find.widgetWithText(GhostButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard post?'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Cancel on a dirty draft confirms; Discard clears and pops', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    container.read(composeControllerProvider.notifier).setCaption('draft');
    expect(container.read(composeControllerProvider).caption, 'draft');

    await tester.tap(find.widgetWithText(GhostButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard post?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(container.read(composeControllerProvider).caption, '');
    // Back on /home — compose is gone.
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Keep editing dismisses the confirm and preserves the draft', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    container.read(composeControllerProvider.notifier).setCaption('draft');

    await tester.tap(find.widgetWithText(GhostButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(container.read(composeControllerProvider).caption, 'draft');
    expect(find.text('home'), findsNothing);
  });

  testWidgets('system back on a dirty draft also confirms', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    container.read(composeControllerProvider.notifier).setCaption('draft');
    // Rebuild so PopScope.canPop reflects the now-dirty draft.
    await tester.pump();

    // Simulate the system back gesture/button: it lands on the root
    // navigator as maybePop, which is what PopScope intercepts.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(nav.maybePop());
    await tester.pumpAndSettle();

    expect(find.text('Discard post?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(container.read(composeControllerProvider).caption, '');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('typing into the textarea updates the caption state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    await tester.enterText(find.byType(TextField), 'sunset on the hill');
    await tester.pump();
    expect(
      container.read(composeControllerProvider).caption,
      'sunset on the hill',
    );
  });

  testWidgets('selected-photo state shows a clear overlay that empties bytes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _openCompose(tester, container);

    await tester.runAsync(() async {
      container
          .read(composeControllerProvider.notifier)
          .debugSeedState(
            ComposeState(photoBytes: _tinyJpeg(), phase: ComposePhase.ready),
          );
      await tester.pump();
      // Give Image.memory a frame to resolve the codec.
      await tester.pump(const Duration(milliseconds: 100));
    });

    final clearIcon = find.byWidgetPredicate(
      (w) => w is Icon && w.color == Colors.white,
    );
    expect(clearIcon, findsOneWidget);
    await tester.tap(clearIcon);
    await tester.pump();
    expect(container.read(composeControllerProvider).photoBytes, isNull);
  });
}
