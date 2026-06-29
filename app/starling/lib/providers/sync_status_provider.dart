import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../widgets/sync_dot.dart';
import 'discovery_provider.dart';
import 'follows_provider.dart';
import 'sync_provider.dart';

part 'sync_status_provider.g.dart';

/// Sync status surfaced in `FeedSyncSearchBar`. Derived from the sync
/// controller's run phase + the live mDNS peer cache + the active
/// follows list.
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSyncedAtSeconds,
    this.reachableFriends = 0,
    this.totalFriends = 0,
  });

  final SyncState state;

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

  final reachable = follows.where((f) => peers.containsKey(f.pubkey)).length;

  if (engineState.phase == SyncRunPhase.syncing) {
    return SyncStatus(
      state: SyncState.syncing,
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
