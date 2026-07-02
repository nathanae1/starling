import 'dart:async';
import 'dart:typed_data';

import 'package:starling/providers/compose_provider.dart';
import 'package:starling/providers/post_provider.dart';
import 'package:starling/screens/compose/compose_screen.dart';
import 'package:starling/screens/compose/preview_screen.dart';
import 'package:starling/services/post_service.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

class _StubPostService implements PostService {
  _StubPostService({this.shouldThrow = false});
  bool shouldThrow;
  int calls = 0;
  Uint8List? lastPhoto;
  String? lastCaption;

  @override
  Future<String> createPost({
    required Uint8List photoBytes,
    required String caption,
  }) async {
    calls++;
    lastPhoto = photoBytes;
    lastCaption = caption;
    if (shouldThrow) throw StateError('nope');
    return 'event-id-1';
  }

  @override
  Future<String> deletePost(String targetEventId) async => 'delete-id';
}

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

Uint8List _tinyJpeg() {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 2; x++) {
      image.setPixelRgb(x, y, 200, 200, 200);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<void> _openPreview(
  WidgetTester tester,
  ProviderContainer container, {
  String caption = 'hello',
}) async {
  container
      .read(composeControllerProvider.notifier)
      .debugSeedState(
        ComposeState(
          photoBytes: _tinyJpeg(),
          caption: caption,
          phase: ComposePhase.ready,
        ),
      );
  await tester.pumpWidget(_app(container));
  await tester.pumpAndSettle();
  // Real navigation pushes /compose first, then /compose/preview, so pops
  // traverse both pages.
  final ctx = tester.element(find.text('home'));
  unawaited(GoRouter.of(ctx).push('/compose'));
  await tester.pumpAndSettle();
  final composeCtx = tester.element(find.byType(ComposeScreen));
  unawaited(GoRouter.of(composeCtx).push('/compose/preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the photo and caption from compose state', (
    tester,
  ) async {
    final stub = _StubPostService();
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(stub)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await _openPreview(tester, container, caption: 'trail morning');
      await tester.pump(const Duration(milliseconds: 100));
    });

    expect(find.text('trail morning'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Post'), findsOneWidget);
    expect(find.widgetWithText(GhostButton, 'Back to edit'), findsOneWidget);
  });

  testWidgets('Back to edit pops back to compose', (tester) async {
    final stub = _StubPostService();
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(stub)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await _openPreview(tester, container);
      await tester.pump(const Duration(milliseconds: 100));
    });

    await tester.tap(find.widgetWithText(GhostButton, 'Back to edit'));
    await tester.pumpAndSettle();

    // Compose is visible again.
    expect(find.byType(ComposeScreen), findsOneWidget);
    // Caption preserved.
    expect(container.read(composeControllerProvider).caption, 'hello');
  });

  testWidgets('Post invokes createPost, clears compose, and pops to home', (
    tester,
  ) async {
    final stub = _StubPostService();
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(stub)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await _openPreview(tester, container, caption: 'sunrise');
      await tester.pump(const Duration(milliseconds: 100));
    });

    await tester.tap(find.widgetWithText(PrimaryButton, 'Post'));
    await tester.pumpAndSettle();

    expect(stub.calls, 1);
    expect(stub.lastCaption, 'sunrise');
    expect(container.read(composeControllerProvider).caption, '');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Post error leaves user on preview with a retry message', (
    tester,
  ) async {
    final stub = _StubPostService(shouldThrow: true);
    final container = ProviderContainer(
      overrides: [postServiceProvider.overrideWithValue(stub)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await _openPreview(tester, container);
      await tester.pump(const Duration(milliseconds: 100));
    });

    await tester.tap(find.widgetWithText(PrimaryButton, 'Post'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't publish"), findsOneWidget);
    // Still on preview — Back to edit visible.
    expect(find.widgetWithText(GhostButton, 'Back to edit'), findsOneWidget);
    // Compose state preserved (caption still there for retry).
    expect(container.read(composeControllerProvider).caption, 'hello');
  });
}
