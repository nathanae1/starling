import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sync/peer_reachability_provider.dart';
import '../widgets/sync_dot.dart';
import 'follows_provider.dart';
import 'publish_activity_provider.dart';
import 'sync_provider.dart';
import 'tor_status_provider.dart';

part 'sync_status_provider.g.dart';

/// Sync status surfaced in `FeedSyncSearchBar`. Derived from the sync
/// controller's run phase + Tor bootstrap progress + the reachability
/// monitor's per-peer state (LAN, Tor, and libp2p — never mDNS alone) +
/// the active follows list.
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.direction,
    this.lastSyncedAtSeconds,
    this.reachableFriends = 0,
    this.totalFriends = 0,
    this.torBootstrapPercent = 0,
    this.lastError,
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

  /// Tor bootstrap progress, for the "Connecting to network… N%" label.
  /// Only meaningful when [state] is [SyncState.connecting]; 0 means the
  /// bootstrap hasn't reported progress yet (omit the number).
  final int torBootstrapPercent;

  /// Raw error from the last sync run, for `debugLog` — user-facing copy
  /// is always the fixed "Sync problem" label, never this string.
  final String? lastError;
}

@riverpod
SyncStatus syncStatus(Ref ref) {
  final engineState = ref.watch(syncControllerProvider);
  final reachability =
      ref.watch(peerReachabilityStateProvider).value ?? const {};
  final follows = ref.watch(followsStreamProvider).value ?? const [];
  final publishing = ref.watch(publishActivityProvider) > 0;
  final tor = ref.watch(torStatusPollerProvider);

  final reachable = follows
      .where((f) => reachability[f.pubkey]?.isReachable ?? false)
      .length;

  // A user-initiated publish takes precedence over a background pull: even
  // mid-sync, show "Publishing…" because that's the action they just took.
  if (publishing) {
    return SyncStatus(
      state: SyncState.syncing,
      direction: SyncDirection.pushing,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: reachable,
      totalFriends: follows.length,
      lastError: engineState.lastError,
    );
  }

  if (engineState.phase == SyncRunPhase.syncing) {
    return SyncStatus(
      state: SyncState.syncing,
      direction: SyncDirection.pulling,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: reachable,
      totalFriends: follows.length,
      lastError: engineState.lastError,
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
  // Cold start: Tor is still bootstrapping (10–30 s) and nobody is
  // reachable yet. That's "coming online", not "offline" — offline is
  // reserved for "no friend reachable on any transport with Tor up".
  if (reachable == 0 && !tor.isReady) {
    return SyncStatus(
      state: SyncState.connecting,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: 0,
      totalFriends: follows.length,
      torBootstrapPercent: tor.bootstrapPercent,
      lastError: engineState.lastError,
    );
  }
  if (reachable == 0) {
    return SyncStatus(
      state: SyncState.offline,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: 0,
      totalFriends: follows.length,
      lastError: engineState.lastError,
    );
  }
  // Peers are reachable but the last run still failed — that's a problem
  // worth a retry affordance, not a quiet "Up to date".
  if (engineState.lastError != null) {
    return SyncStatus(
      state: SyncState.problem,
      lastSyncedAtSeconds: engineState.lastSyncAt,
      reachableFriends: reachable,
      totalFriends: follows.length,
      lastError: engineState.lastError,
    );
  }
  return SyncStatus(
    state: SyncState.synced,
    lastSyncedAtSeconds: engineState.lastSyncAt,
    reachableFriends: reachable,
    totalFriends: follows.length,
  );
}
