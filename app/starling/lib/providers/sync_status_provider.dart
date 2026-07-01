import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../widgets/sync_dot.dart';
import 'discovery_provider.dart';
import 'follows_provider.dart';
import 'publish_activity_provider.dart';
import 'sync_provider.dart';

part 'sync_status_provider.g.dart';

/// Sync status surfaced in `FeedSyncSearchBar`. Derived from the sync
/// controller's run phase + the live mDNS peer cache + the active
/// follows list.
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.direction,
    this.lastSyncedAtSeconds,
    this.reachableFriends = 0,
    this.totalFriends = 0,
  });

  final SyncState state;

  /// Only meaningful when [state] is [SyncState.syncing]: whether the app is
  /// pulling friends' feeds in ("Loading feeds…") or pushing the user's own
  /// post out ("Publishing…").
  final SyncDirection? direction;

  /// Unix seconds. Null means "not yet synced this session".
  final int? lastSyncedAtSeconds;

  final int reachableFriends;

  /// Total accepted follows — the denominator for the "N/M friends
  /// reachable" status label.
  final int totalFriends;
}

@riverpod
SyncStatus syncStatus(Ref ref) {
  final engineState = ref.watch(syncControllerProvider);
  final peers = ref.watch(discoveryControllerProvider).value ?? const {};
  final follows = ref.watch(followsStreamProvider).value ?? const [];
  final publishing = ref.watch(publishActivityProvider) > 0;

  final reachable = follows.where((f) => peers.containsKey(f.pubkey)).length;

  // A user-initiated publish takes precedence over a background pull: even
  // mid-sync, show "Publishing…" because that's the action they just took.
  if (publishing) {
    return SyncStatus(
      state: SyncState.syncing,
      direction: SyncDirection.pushing,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: reachable,
      totalFriends: follows.length,
    );
  }

  if (engineState.phase == SyncRunPhase.syncing) {
    return SyncStatus(
      state: SyncState.syncing,
      direction: SyncDirection.pulling,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: reachable,
      totalFriends: follows.length,
    );
  }
  if (follows.isEmpty) {
    return SyncStatus(
      state: SyncState.synced,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: 0,
      totalFriends: 0,
    );
  }
  if (reachable == 0) {
    return SyncStatus(
      state: SyncState.offline,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: 0,
      totalFriends: follows.length,
    );
  }
  return SyncStatus(
    state: SyncState.synced,
    lastSyncedAtSeconds: engineState.lastSyncAt,
    reachableFriends: reachable,
    totalFriends: follows.length,
  );
}
