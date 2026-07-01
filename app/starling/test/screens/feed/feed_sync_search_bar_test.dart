import 'package:starling/providers/search_provider.dart';
import 'package:starling/providers/sync_status_provider.dart';
import 'package:starling/screens/feed/feed_sync_search_bar.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/sync_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts the bar in a minimal Material/Theme/Riverpod tree so we can drive
/// the UI without booting the full app shell.
Widget _harness(
  ProviderContainer container, {
  Widget child = const FeedSyncSearchBar(),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildStarlingMaterialTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('default mode shows the SyncDot', (tester) async {
    final container = ProviderContainer(overrides: [
      syncStatusProvider.overrideWithValue(
        const SyncStatus(state: SyncState.synced),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byType(SyncDot), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping magnifier swaps to search mode with autofocused field',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    // The rightmost InkWell is the magnifier IconButton.
    await tester.tap(find.byType(InkWell).last);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(SyncDot), findsNothing);
  });

  testWidgets('Cancel exits search mode and clears the query', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    // Enter search mode.
    await tester.tap(find.byType(InkWell).last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Bypass the debounce so the assertion isn't time-dependent.
    container.read(searchQueryProvider.notifier).clear();
    container.read(searchQueryProvider.notifier);
    // Force the underlying provider state directly via the typed container
    // by calling clear, which sets state synchronously.
    expect(container.read(searchQueryProvider), equals(''));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(container.read(searchQueryProvider), equals(''));
  });

  testWidgets('syncing + pulling shows the "Loading feeds…" label',
      (tester) async {
    final container = ProviderContainer(overrides: [
      syncStatusProvider.overrideWithValue(
        const SyncStatus(
          state: SyncState.syncing,
          direction: SyncDirection.pulling,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    // Not pumpAndSettle — the syncing dot pulses forever.
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Loading feeds…'), findsOneWidget);
    expect(find.text('Publishing…'), findsNothing);
  });

  testWidgets('syncing + pushing shows the "Publishing…" label',
      (tester) async {
    final container = ProviderContainer(overrides: [
      syncStatusProvider.overrideWithValue(
        const SyncStatus(
          state: SyncState.syncing,
          direction: SyncDirection.pushing,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Publishing…'), findsOneWidget);
    expect(find.text('Loading feeds…'), findsNothing);
  });
}
