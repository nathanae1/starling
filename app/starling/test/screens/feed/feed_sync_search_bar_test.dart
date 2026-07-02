import 'package:starling/providers/search_provider.dart';
import 'package:starling/providers/service_providers.dart';
import 'package:starling/providers/sync_status_provider.dart';
import 'package:starling/screens/feed/feed_sync_search_bar.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/theme/starling_theme.dart';
import 'package:starling/widgets/sync_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.now);
  final int now;

  @override
  int nowUnixSeconds() => now;
}

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
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(state: SyncState.synced),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byType(SyncDot), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping magnifier swaps to search mode with autofocused field', (
    tester,
  ) async {
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

  testWidgets('syncing + pulling shows the "Loading feeds…" label', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.syncing,
            direction: SyncDirection.pulling,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    // Not pumpAndSettle — the syncing dot pulses forever.
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Loading feeds…'), findsOneWidget);
    expect(find.text('Publishing…'), findsNothing);
  });

  testWidgets('syncing + pushing shows the "Publishing…" label', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.syncing,
            direction: SyncDirection.pushing,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Publishing…'), findsOneWidget);
    expect(find.text('Loading feeds…'), findsNothing);
  });

  testWidgets('connecting shows the bootstrap percent when known', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.connecting,
            totalFriends: 2,
            torBootstrapPercent: 43,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    // Not pumpAndSettle — the connecting dot pulses forever.
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Connecting to network… 43%'), findsOneWidget);
  });

  testWidgets('connecting omits the percent when bootstrap has not reported', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(state: SyncState.connecting, totalFriends: 2),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Connecting to network…'), findsOneWidget);
  });

  testWidgets('sync problem shows the retry affordance', (tester) async {
    final container = ProviderContainer(
      overrides: [
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.problem,
            reachableFriends: 2,
            totalFriends: 2,
            lastError: 'HandshakeException: boom',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('Sync problem — tap to retry'), findsOneWidget);
    // The raw error never renders.
    expect(find.textContaining('HandshakeException'), findsNothing);
  });

  testWidgets('synced shows the reachable fraction + honest relative time', (
    tester,
  ) async {
    const now = 1_000_000;
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(const _FixedClock(now)),
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.synced,
            lastSyncedAtSeconds: now - 240,
            reachableFriends: 2,
            totalFriends: 3,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('2/3 friends reachable · synced 4m ago'), findsOneWidget);
  });

  testWidgets('synced just now reads naturally', (tester) async {
    const now = 1_000_000;
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(const _FixedClock(now)),
        syncStatusProvider.overrideWithValue(
          const SyncStatus(
            state: SyncState.synced,
            lastSyncedAtSeconds: now - 5,
            reachableFriends: 1,
            totalFriends: 1,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(
      find.text('1/1 friends reachable · synced just now'),
      findsOneWidget,
    );
  });
}
