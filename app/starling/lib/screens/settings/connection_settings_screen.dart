import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/follow_profile_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/relay_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/sync_provider.dart';
import '../../services/types.dart';
import '../../sync/peer_reachability_monitor.dart';
import '../../sync/peer_reachability_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/starling_address.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sheet.dart';
import '../../widgets/starling_badge.dart';
import '../friends/scan_screen.dart';

/// Surfaces the per-peer reachability state maintained by
/// [PeerReachabilityMonitor]. Used for connection troubleshooting:
/// shows LAN/Tor status, last error, last-change timestamp, and the
/// validated endpoint when reachable. The user can force a re-probe.
class ConnectionSettingsScreen extends ConsumerWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final followsAsync = ref.watch(followsStreamProvider);
    final stateAsync = ref.watch(peerReachabilityStateProvider);

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            const _RelaySection(),
            Expanded(
              child: followsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorView(message: '$e'),
                data: (follows) {
                  if (follows.isEmpty) {
                    return const _EmptyView();
                  }
                  final state = stateAsync.maybeWhen(
                    data: (s) => s,
                    orElse: () => const <String, PeerReachability>{},
                  );
                  return RefreshIndicator(
                    onRefresh: () => _refreshAll(ref, follows),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: follows.length,
                      itemBuilder: (_, i) {
                        final follow = follows[i];
                        return _PeerTile(
                          follow: follow,
                          reachability: state[follow.pubkey],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header();

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final follows = await ref.read(storageServiceProvider).getFollows();
      await _refreshAll(ref, follows);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

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
              'Connection',
              style: starling.typography.h3.copyWith(
                fontFamily: 'Fraunces',
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // While a refresh runs, swap the icon button for an explicit
          // spinner + label so the action's progress is obvious (the probe
          // can take a few seconds over Tor).
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        starling.colors.sage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Refreshing…', style: starling.typography.micro),
                ],
              ),
            )
          else
            StarlingIconButton(
              onPressed: _refresh,
              semanticLabel: 'Refresh all',
              tooltip: 'Refresh all',
              child: const Icon(LucideIcons.refreshCw, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Plan 15 — pair/unpair an always-on relay and show its status. Sits
/// above the per-peer list so it reads as "my reach" before "their reach."
class _RelaySection extends ConsumerStatefulWidget {
  const _RelaySection();

  @override
  ConsumerState<_RelaySection> createState() => _RelaySectionState();
}

class _RelaySectionState extends ConsumerState<_RelaySection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final relay = ref.watch(pairedRelayControllerProvider).value;
    final serviceReady = ref.watch(relayPairingServiceProvider).value != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: starling.colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Relay',
                  style: starling.typography.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: starling.colors.ink,
                  ),
                ),
              ),
              if (relay == null)
                SecondaryButton(label: 'Pair a relay', onPressed: _openScanner)
              else
                SecondaryButton(
                  label: _busy ? 'Unpairing…' : 'Unpair',
                  onPressed: (_busy || !serviceReady) ? null : _unpair,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            relay == null
                ? 'No relay paired — friends only reach you while your phone '
                      'is online.'
                : '${_shortOnion(relay.relayOnion)} · '
                      '${relay.backfillComplete ? 'synced' : 'syncing…'}',
            style: starling.typography.micro.copyWith(
              color: starling.colors.stone,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _openScanner() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));
  }

  Future<void> _unpair() async {
    final confirmed = await showStarlingSheet<bool>(
      context: context,
      builder: (ctx) {
        final starling = StarlingTheme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Unpair this relay?', style: starling.typography.h3),
            const SizedBox(height: 8),
            Text(
              'Friends will stop reaching your feed through the relay. Its '
              'stored copy stays until you remove it from the relay’s admin '
              'page.',
              style: starling.typography.body,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Unpair',
              onPressed: () => Navigator.of(ctx).pop(true),
              block: true,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(relayPairingServiceProvider).value;
      await service?.unpair();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t unpair — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _shortOnion(String onion) {
    final host = onion.split(':').first;
    return host.length > 16 ? '${host.substring(0, 16)}…' : host;
  }
}

/// Triggers transport probes AND a per-peer sync for every follow. The
/// transport probes refresh LAN/Tor reachability; the per-peer sync
/// pulls any pending feed-key rotation inline via the manifest, which
/// is what keeps the "Key" status row accurate.
Future<void> _refreshAll(WidgetRef ref, List<Follow> follows) async {
  final monitor = ref.read(peerReachabilityMonitorProvider);
  final engine = ref.read(syncEngineProvider);
  await Future.wait([
    monitor.refreshNow(),
    ...follows.map((f) async {
      try {
        await engine.syncOnePeerByPubkey(f.pubkey);
      } catch (_) {
        // syncOnePeer already logs; swallow per-peer failures so the
        // refresh as a whole always completes.
      }
    }),
  ]);
}

class _PeerTile extends ConsumerWidget {
  const _PeerTile({required this.follow, required this.reachability});

  final Follow follow;
  final PeerReachability? reachability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final profileAsync = ref.watch(followProfileProvider(follow.pubkey));
    final name = profileAsync.maybeWhen(
      data: (p) => p.displayName,
      orElse: () => shortStarlingAddress(follow.pubkey),
    );

    final lan = reachability?.transports[PeerTransport.lan];
    final tor = reachability?.transports[PeerTransport.tor];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: starling.colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: starling.typography.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: starling.colors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                shortStarlingAddress(follow.pubkey),
                style: starling.typography.micro.copyWith(
                  color: starling.colors.stone,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TransportRow(label: 'LAN', status: lan),
          const SizedBox(height: 4),
          _TransportRow(label: 'Tor', status: tor),
          const SizedBox(height: 4),
          _KeyHealthRow(follow: follow),
        ],
      ),
    );
  }
}

enum _KeyHealth { unknown, ok, stale }

class _KeyHealthRow extends StatelessWidget {
  const _KeyHealthRow({required this.follow});

  final Follow follow;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final health = _classify(follow);
    // Same success/danger/stone vocabulary as the transport chips above.
    final (label, color) = switch (health) {
      _KeyHealth.ok => ('Fresh', starling.colors.success),
      _KeyHealth.stale => ('Stale', starling.colors.danger),
      _KeyHealth.unknown => ('Unknown', starling.colors.stone),
    };
    final detail = _detail(follow, health);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            'Key',
            style: starling.typography.small.copyWith(
              color: starling.colors.graphite,
            ),
          ),
        ),
        const SizedBox(width: 8),
        StarlingBadge(label: label, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: detail == null
              ? const SizedBox.shrink()
              : Text(
                  detail,
                  style: starling.typography.micro.copyWith(
                    color: starling.colors.stone,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }

  static _KeyHealth _classify(Follow follow) {
    if (follow.lastDecryptFailureAt != null) return _KeyHealth.stale;
    if (follow.lastSyncedAt > 0) return _KeyHealth.ok;
    return _KeyHealth.unknown;
  }

  static String? _detail(Follow follow, _KeyHealth health) {
    if (health == _KeyHealth.stale && follow.lastDecryptFailureAt != null) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        follow.lastDecryptFailureAt! * 1000,
      );
      return 'decrypt failed ${_relativeTime(t)} — re-pair if not recovered';
    }
    if (health == _KeyHealth.ok && follow.lastSyncedAt > 0) {
      final t = DateTime.fromMillisecondsSinceEpoch(follow.lastSyncedAt * 1000);
      return 'verified ${_relativeTime(t)}';
    }
    return null;
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.label, required this.status});

  final String label;
  final TransportStatus? status;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final state = status?.state ?? TransportState.unknown;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: starling.typography.small.copyWith(
              color: starling.colors.graphite,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StatusChip(state: state),
        const SizedBox(width: 8),
        Expanded(child: _TransportDetails(status: status)),
      ],
    );
  }
}

class _TransportDetails extends StatelessWidget {
  const _TransportDetails({required this.status});

  final TransportStatus? status;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final s = status;
    if (s == null) {
      return Text(
        '—',
        style: starling.typography.micro.copyWith(color: starling.colors.stone),
      );
    }
    final lines = <String>[];
    if (s.endpointHint != null) {
      lines.add(s.endpointHint!);
    }
    if (s.state == TransportState.unreachable && s.lastError != null) {
      lines.add(s.lastError!);
      if (s.consecutiveFailures > 1) {
        lines.add('${s.consecutiveFailures} consecutive failures');
      }
    }
    if (s.lastChange != null) {
      lines.add('updated ${_relativeTime(s.lastChange!)}');
    }
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              line,
              style: starling.typography.micro.copyWith(
                color: starling.colors.stone,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final TransportState state;

  @override
  Widget build(BuildContext context) {
    final colors = StarlingTheme.of(context).colors;
    // Shared status vocabulary/colors with the network screen's quick-status
    // badges: success = reachable, warning = probing/in-progress, danger =
    // unreachable, stone = unknown.
    final (label, color) = switch (state) {
      TransportState.reachable => ('Reachable', colors.success),
      TransportState.probing => ('Probing…', colors.warning),
      TransportState.unreachable => ('Unreachable', colors.danger),
      TransportState.unknown => ('Unknown', colors.stone),
    };
    return StarlingBadge(label: label, color: color);
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Add friends to see their connection status here.',
          textAlign: TextAlign.center,
          style: starling.typography.small.copyWith(
            color: starling.colors.graphite,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: starling.typography.small.copyWith(
            color: starling.colors.danger,
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime t) {
  final delta = DateTime.now().difference(t);
  if (delta.inSeconds < 5) return 'just now';
  if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}
