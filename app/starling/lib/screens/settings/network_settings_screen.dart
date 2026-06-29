import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/foreground_service_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/sync_provider.dart';
import '../../providers/sync_status_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/starling_badge.dart';
import '../../widgets/starling_card.dart';
import '../../widgets/sync_dot.dart';

/// Plan 14 Phase E — single screen that aggregates the four moving parts of
/// "how is Starling reachable right now": sync state, Tor onion + circuits,
/// LAN peers via mDNS, and the local HTTP server port. Plus the Android-only
/// foreground-service toggle and an informational note for iOS.
///
/// Consumes existing providers — no new state plumbing needed. Per-peer
/// detail lives in `connection_settings_screen.dart`; this screen links to
/// it rather than duplicating the per-friend transport breakdown.
class NetworkSettingsScreen extends ConsumerWidget {
  const NetworkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final syncStatus = ref.watch(syncStatusProvider);
    final engineState = ref.watch(syncControllerProvider);
    final tor = ref.watch(torServiceProvider);
    final torStatus = tor.getStatus();
    final onion = ref.watch(onionAddressProvider);
    final port = ref.watch(httpServerControllerProvider).value;

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onRefresh: () =>
                  ref.read(syncControllerProvider.notifier).syncNow(),
              syncing: engineState.phase == SyncRunPhase.syncing,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                children: [
                  _QuickStatus(
                    syncState: syncStatus.state,
                    reachableFriends: syncStatus.reachableFriends,
                    torBootstrapPercent: torStatus.bootstrapPercent,
                    torReady: torStatus.isReady,
                  ),
                  const SizedBox(height: 12),
                  _SyncCard(
                    state: syncStatus.state,
                    lastSyncedAtSeconds: syncStatus.lastSyncedAtSeconds,
                    reachableFriends: syncStatus.reachableFriends,
                    lastError: engineState.lastError,
                  ),
                  const SizedBox(height: 12),
                  _TorCard(
                    bootstrapPercent: torStatus.bootstrapPercent,
                    circuitCount: torStatus.circuitCount,
                    isReady: torStatus.isReady,
                    onionAddress: onion,
                  ),
                  const SizedBox(height: 12),
                  _LanCard(reachableFriends: syncStatus.reachableFriends),
                  const SizedBox(height: 12),
                  _ServerCard(port: port),
                  const SizedBox(height: 12),
                  if (Platform.isAndroid)
                    const _AndroidBackgroundCard()
                  else
                    const _IosBackgroundCard(),
                  const SizedBox(height: 12),
                  _PerPeerLink(
                    onTap: () => context.push('/settings/connection'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh, required this.syncing});

  final VoidCallback onRefresh;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: starling.colors.hairline)),
      ),
      child: Row(
        children: [
          StarlingIconButton(
            onPressed: () => context.pop(),
            semanticLabel: 'Back',
            child: const Icon(LucideIcons.arrowLeft, size: 20),
          ),
          Expanded(
            child: Text(
              'Network',
              style: starling.typography.h3.copyWith(
                fontFamily: 'Fraunces',
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          StarlingIconButton(
            onPressed: syncing ? null : onRefresh,
            semanticLabel: 'Sync now',
            tooltip: 'Sync now',
            child: Icon(
              LucideIcons.refreshCw,
              size: 20,
              color: syncing ? starling.colors.stone : starling.colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line status summary pinned to the top of the screen: overall sync
/// state · reachable-friend count · Tor readiness. Lets the user read "how
/// am I reachable right now" at a glance without scrolling the detail cards.
/// Uses [StarlingBadge] so the status vocabulary/colors match the per-peer
/// chips on the Connection screen.
class _QuickStatus extends StatelessWidget {
  const _QuickStatus({
    required this.syncState,
    required this.reachableFriends,
    required this.torBootstrapPercent,
    required this.torReady,
  });

  final SyncState syncState;
  final int reachableFriends;
  final int torBootstrapPercent;
  final bool torReady;

  @override
  Widget build(BuildContext context) {
    final colors = StarlingTheme.of(context).colors;
    final (syncLabel, syncColor) = switch (syncState) {
      SyncState.synced => ('Up to date', colors.success),
      SyncState.syncing => ('Syncing…', colors.warning),
      SyncState.offline => ('Offline', colors.stone),
    };
    final torColor = torReady
        ? colors.success
        : (torBootstrapPercent > 0 ? colors.warning : colors.stone);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StarlingBadge(label: syncLabel, color: syncColor),
        StarlingBadge(
          label: '$reachableFriends reachable',
          color: reachableFriends > 0 ? colors.success : colors.stone,
          icon: LucideIcons.users,
        ),
        StarlingBadge(
          label: torReady ? 'Tor 100%' : 'Tor $torBootstrapPercent%',
          color: torColor,
          icon: LucideIcons.shield,
        ),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value, this.valueWidget});

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: starling.typography.small.copyWith(
                color: starling.colors.graphite,
              ),
            ),
          ),
          Expanded(
            child:
                valueWidget ??
                Text(
                  value,
                  style: starling.typography.small.copyWith(
                    color: starling.colors.ink,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.state,
    required this.lastSyncedAtSeconds,
    required this.reachableFriends,
    required this.lastError,
  });

  final SyncState state;
  final int? lastSyncedAtSeconds;
  final int reachableFriends;
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return StarlingCard(
      title: 'Sync',
      icon: LucideIcons.refreshCw,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValue(
            label: 'Status',
            value: '',
            valueWidget: Row(
              children: [
                SyncDot(state: state),
                const SizedBox(width: 8),
                Text(_syncLabel(state), style: starling.typography.small),
              ],
            ),
          ),
          _KeyValue(
            label: 'Last sync',
            value: _formatTimestamp(lastSyncedAtSeconds),
          ),
          _KeyValue(
            label: 'Reachable',
            value:
                '$reachableFriends friend${reachableFriends == 1 ? '' : 's'}',
          ),
          // Always rendered — a grayed em-dash stands in for "no error" so
          // the card height stays stable instead of jumping when an error
          // appears or clears.
          _KeyValue(
            label: 'Last error',
            value: '',
            valueWidget: lastError == null
                ? Text(
                    '—',
                    style: starling.typography.small.copyWith(
                      color: starling.colors.stone,
                    ),
                  )
                : Text(
                    lastError!,
                    style: starling.typography.small.copyWith(
                      color: starling.colors.danger,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _syncLabel(SyncState s) => switch (s) {
    SyncState.synced => 'Up to date',
    SyncState.syncing => 'Syncing…',
    SyncState.offline => 'Offline',
  };
}

class _TorCard extends StatelessWidget {
  const _TorCard({
    required this.bootstrapPercent,
    required this.circuitCount,
    required this.isReady,
    required this.onionAddress,
  });

  final int bootstrapPercent;
  final int circuitCount;
  final bool isReady;
  final String? onionAddress;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return StarlingCard(
      title: 'Tor',
      icon: LucideIcons.shield,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValue(
            label: 'Bootstrap',
            value: isReady ? '100% (ready)' : '$bootstrapPercent%',
          ),
          _KeyValue(label: 'Circuits', value: '$circuitCount'),
          _KeyValue(
            label: 'Onion',
            value: '',
            valueWidget: onionAddress == null
                ? Text(
                    'Not published yet',
                    style: starling.typography.small.copyWith(
                      color: starling.colors.stone,
                    ),
                  )
                : InkWell(
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: onionAddress!),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Onion address copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            onionAddress!,
                            style: starling.typography.small.copyWith(
                              fontFamily: 'IBMPlexMono',
                              color: starling.colors.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.copy,
                          size: 14,
                          color: starling.colors.graphite,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LanCard extends StatelessWidget {
  const _LanCard({required this.reachableFriends});

  final int reachableFriends;

  @override
  Widget build(BuildContext context) {
    return StarlingCard(
      title: 'Local Wi-Fi',
      icon: LucideIcons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValue(
            label: 'Reachable',
            value:
                '$reachableFriends friend${reachableFriends == 1 ? '' : 's'} on this network',
          ),
          const _KeyValue(
            label: 'Service',
            value: '_starling._tcp (mDNS/Bonjour)',
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.port});

  final int? port;

  @override
  Widget build(BuildContext context) {
    return StarlingCard(
      title: 'Local server',
      icon: LucideIcons.server,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValue(label: 'Port', value: port == null ? 'Not bound' : '$port'),
          const _KeyValue(label: 'Binding', value: '0.0.0.0 (LAN + Tor onion)'),
        ],
      ),
    );
  }
}

class _AndroidBackgroundCard extends ConsumerWidget {
  const _AndroidBackgroundCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final runningAsync = ref.watch(foregroundServiceStateProvider);
    final running = runningAsync.value ?? false;
    return StarlingCard(
      title: 'Background mode',
      icon: LucideIcons.batteryCharging,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keep Starling running',
                      style: starling.typography.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: starling.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your phone stays reachable to friends in the background. '
                      'Uses more battery.',
                      style: starling.typography.small.copyWith(
                        color: starling.colors.graphite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: running,
                onChanged: runningAsync.isLoading
                    ? null
                    : (v) async {
                        final notifier = ref.read(
                          foregroundServiceStateProvider.notifier,
                        );
                        final ok = await notifier.setEnabled(v);
                        if (!context.mounted) return;
                        if (v && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Notification permission required for background mode.',
                              ),
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            running
                ? 'Background sync also runs every 15 min via WorkManager.'
                : 'Background sync runs every 15 min via WorkManager when possible.',
            style: starling.typography.micro.copyWith(
              color: StarlingTheme.of(context).colors.stone,
            ),
          ),
        ],
      ),
    );
  }
}

class _IosBackgroundCard extends StatelessWidget {
  const _IosBackgroundCard();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return StarlingCard(
      title: 'Background mode',
      icon: LucideIcons.batteryCharging,
      child: Text(
        'iOS controls background sync timing. Starling checks when iOS '
        'grants permission, usually less often than once per hour. '
        'When your phone is plugged in and idle, longer background '
        'sessions can use Tor.',
        style: starling.typography.small.copyWith(
          color: starling.colors.graphite,
        ),
      ),
    );
  }
}

class _PerPeerLink extends StatelessWidget {
  const _PerPeerLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: starling.colors.hairline),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.users, size: 18, color: starling.colors.graphite),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Per-friend reachability',
                    style: starling.typography.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: starling.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'See LAN/Tor status and key freshness for each friend',
                    style: starling.typography.micro,
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: starling.colors.stone,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(int? unixSeconds) {
  if (unixSeconds == null || unixSeconds == 0) return 'Never';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
