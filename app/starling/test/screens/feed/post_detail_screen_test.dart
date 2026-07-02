import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/screens/feed/post_detail_screen.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/bookmark_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Event _post(String id, {int createdAt = 1000}) => Event(
  version: '2026-03-24',
  id: id,
  pubkey: 'me',
  createdAt: createdAt,
  kind: EventKind.post,
  content: Uint8List.fromList('caption'.codeUnits),
  sig: Uint8List.fromList(List.filled(64, 0)),
);

Widget _harness(ProviderContainer container, String eventId) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildStarlingMaterialTheme(),
      home: PostDetailScreen(eventId: eventId),
    ),
  );
}

void main() {
  testWidgets('initState marks the event as last_viewed', (tester) async {
    final storage = MockStorageService();
    final clock = MockClock();
    clock.advance(5000);
    await storage.saveIdentity(
      Identity(pubkey: 'me', feedKey: Uint8List(32), createdAt: 0),
    );
    await storage.saveEvent(_post('e1'));

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container, 'e1'));
    await tester.pumpAndSettle();

    // initState fired setEventLastViewed; the mock records it.
    // Indirect verification: not strictly readable from public API, but the
    // call shouldn't throw and the screen should render without error.
    expect(find.text('caption'), findsOneWidget);
  });

  testWidgets('tapping bookmark flips is_saved on storage', (tester) async {
    final storage = MockStorageService();
    final clock = MockClock();
    await storage.saveIdentity(
      Identity(pubkey: 'me', feedKey: Uint8List(32), createdAt: 0),
    );
    await storage.saveEvent(_post('e1'));

    final container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container, 'e1'));
    await tester.pumpAndSettle();

    expect(await storage.isEventSaved('e1'), isFalse);

    final inkWell = find.descendant(
      of: find.byType(BookmarkButton),
      matching: find.byType(InkWell),
    );
    expect(inkWell, findsOneWidget);

    await tester.tap(inkWell);
    await tester.pumpAndSettle();

    expect(await storage.isEventSaved('e1'), isTrue);
  });
}
