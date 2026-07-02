import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/minute_ticker_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/sync_provider.dart';
import '../../providers/sync_status_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/time_ago.dart';
import '../../widgets/buttons.dart';
import '../../widgets/starling_icon.dart';
import '../../widgets/sync_dot.dart';

/// Single-row top-of-feed widget. Two modes:
///   - default: SyncDot + status text + magnifier
///   - search: magnifier + autofocused TextField + Cancel
class FeedSyncSearchBar extends ConsumerStatefulWidget {
  const FeedSyncSearchBar({super.key});

  @override
  ConsumerState<FeedSyncSearchBar> createState() => _FeedSyncSearchBarState();
}

class _FeedSyncSearchBarState extends ConsumerState<FeedSyncSearchBar> {
  bool _searching = false;
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _enterSearch() {
    setState(() => _searching = true);
    // Autofocus on next frame so the TextField is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _exitSearch() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).clear();
    setState(() => _searching = false);
    _focus.unfocus();
  }

  /// Offline and sync-problem statuses are tappable — kick a fresh sync
  /// pass. Errors land in `SyncEngineState.lastError`, which
  /// `syncStatusProvider` folds back into this row, so we swallow them here.
  Future<void> _retrySync() async {
    try {
      await ref.read(syncControllerProvider.notifier).syncNow();
    } catch (_) {
      // Surfaced via the status row itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: starling.colors.paper,
        border: Border(bottom: BorderSide(color: starling.colors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Soft cross-fade between the two modes instead of an abrupt swap.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _searching
            ? KeyedSubtree(
                key: const ValueKey('search'),
                child: _buildSearchRow(starling),
              )
            : KeyedSubtree(
                key: const ValueKey('sync'),
                child: _buildSyncRow(starling),
              ),
      ),
    );
  }

  Widget _buildSyncRow(StarlingTheme starling) {
    final status = ref.watch(syncStatusProvider);
    // 60 s heartbeat keeps the "synced Nm ago" clause honest while idle.
    ref.watch(minuteTickerProvider);
    final now = ref.watch(clockProvider).nowUnixSeconds();
    final tappable =
        status.state == SyncState.offline || status.state == SyncState.problem;

    final statusRow = Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SyncDot(state: status.state, direction: status.direction),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            _statusLabel(status, now),
            style: starling.typography.small.copyWith(
              color: starling.colors.graphite,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (tappable) ...[
          const SizedBox(width: 8),
          StarlingIcon(
            LucideIcons.refreshCw,
            size: 14,
            color: starling.colors.sageDeep,
          ),
        ],
      ],
    );

    return Row(
      children: [
        Expanded(
          child: tappable
              ? Semantics(
                  button: true,
                  label: status.state == SyncState.problem
                      ? 'Sync problem. Tap to retry sync.'
                      : 'Offline. Tap to retry sync.',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_retrySync()),
                    child: statusRow,
                  ),
                )
              : statusRow,
        ),
        StarlingIconButton(
          onPressed: _enterSearch,
          semanticLabel: 'Search',
          tooltip: 'Search',
          child: const Icon(LucideIcons.search, size: 18),
        ),
      ],
    );
  }

  Widget _buildSearchRow(StarlingTheme starling) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: StarlingIcon(
            LucideIcons.search,
            size: 18,
            color: starling.colors.graphite,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: (value) =>
                ref.read(searchQueryProvider.notifier).set(value),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: 'Search posts and friends',
              hintStyle: starling.typography.small.copyWith(
                color: starling.colors.stone,
              ),
            ),
            style: starling.typography.body,
            cursorColor: starling.colors.sage,
          ),
        ),
        GhostButton(label: 'Cancel', onPressed: _exitSearch),
      ],
    );
  }

  String _statusLabel(SyncStatus status, int nowUnixSeconds) {
    switch (status.state) {
      case SyncState.synced:
        // Reachability as a fraction ("3/5 friends reachable") is the
        // primary signal; when it last synced is the secondary clause.
        final primary = status.totalFriends > 0
            ? '${status.reachableFriends}/${status.totalFriends} friends reachable'
            : 'Up to date';
        final syncedAt = status.lastSyncedAtSeconds;
        if (syncedAt == null) return primary;
        return '$primary · ${_syncedClause(syncedAt, nowUnixSeconds)}';
      case SyncState.syncing:
        return status.direction == SyncDirection.pushing
            ? 'Publishing…'
            : 'Loading feeds…';
      case SyncState.connecting:
        return status.torBootstrapPercent > 0
            ? 'Connecting to network… ${status.torBootstrapPercent}%'
            : 'Connecting to network…';
      case SyncState.offline:
        return 'Offline — tap to retry';
      case SyncState.problem:
        return 'Sync problem — tap to retry';
    }
  }

  String _syncedClause(int syncedAtSeconds, int nowUnixSeconds) {
    final rel = timeAgo(syncedAtSeconds, nowUnixSeconds: nowUnixSeconds);
    // "just now"/"yesterday" already read as complete phrases.
    if (rel == 'just now' || rel == 'yesterday') return 'synced $rel';
    return 'synced $rel ago';
  }
}
