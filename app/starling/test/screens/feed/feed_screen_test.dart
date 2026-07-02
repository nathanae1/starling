import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/screens/feed/feed_screen.dart';
import 'package:starling/screens/feed/post_card.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/empty_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _harness(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/feed',
    routes: [
      GoRoute(path: '/feed', builder: (_, _) => const FeedScreen()),
      GoRoute(
        path: '/invite',
        builder: (_, _) => const Scaffold(body: Text('invite stub')),
      ),
      GoRoute(
        path: '/feed/post/:id',
        builder: (_, _) => const Scaffold(body: Text('post detail stub')),
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

Event _post(String id, {int createdAt = 1000}) => Event(
  version: '2026-03-24',
  id: id,
  pubkey: 'me',
  createdAt: createdAt,
  kind: EventKind.post,
  content: Uint8List.fromList('hello world'.codeUnits),
  sig: Uint8List.fromList(List.filled(64, 0)),
);

void main() {
  testWidgets('empty feed renders the EmptyFeed CTA', (tester) async {
    final storage = MockStorageService();
    await storage.saveIdentity(
      Identity(pubkey: 'me', feedKey: Uint8List(32), createdAt: 0),
    );

    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyFeed), findsOneWidget);
    expect(find.text('Add a friend to get started'), findsOneWidget);
  });

  testWidgets('populated feed renders one PostCard per event + trailing line', (
    tester,
  ) async {
    final storage = MockStorageService();
    await storage.saveIdentity(
      Identity(pubkey: 'me', feedKey: Uint8List(32), createdAt: 0),
    );
    await storage.saveEvent(_post('e1', createdAt: 1000));
    await storage.saveEvent(_post('e2', createdAt: 2000));

    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byType(PostCard), findsNWidgets(2));
    expect(find.byType(EmptyFeed), findsNothing);
    expect(find.text("you're all caught up."), findsOneWidget);
  });
}
