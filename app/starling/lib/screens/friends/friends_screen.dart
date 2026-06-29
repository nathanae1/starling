import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/follow_profile_provider.dart';
import '../../providers/follow_provider.dart';
import '../../providers/follow_requests_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/follow_service.dart';
import '../../services/types.dart';
import '../../theme/starling_theme.dart';
import '../../utils/pubkey_format.dart';
import '../../utils/time_ago.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/encrypted_avatar.dart';
import '../../widgets/qr_invite_sheet.dart';
import '../../widgets/sheet.dart';
import '../../widgets/top_bar.dart';
import 'friend_actions_sheet.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final followsAsync = ref.watch(followsStreamProvider);
    final inboundAsync = ref.watch(inboundRequestsStreamProvider);
    final outboundAsync = ref.watch(outboundRequestsStreamProvider);

    final follows = followsAsync.value ?? const <Follow>[];
    final inbound = inboundAsync.value ?? const <FollowRequest>[];
    final outbound = outboundAsync.value ?? const <FollowRequest>[];
    final inboundFollowersAsync = ref.watch(inboundFollowersStreamProvider);
    final inboundFollowers =
        inboundFollowersAsync.value ?? const <FollowRequest>[];
    // A peer who shows up here AND in `follows` is mutual — drop them
    // from the "Follows you" section to avoid duplication.
    final mutualPubkeys = follows.map((f) => f.pubkey).toSet();
    final followersOnly = inboundFollowers
        .where((r) => !mutualPubkeys.contains(r.pubkey))
        .toList();
    // Inbound follower status keyed by pubkey, so a friend row can surface
    // when our follow-back accept to them is still in flight (otherwise the
    // dedup above hides the half-finished connection entirely).
    final inboundByPubkey = <String, FollowRequest>{
      for (final r in inboundFollowers) r.pubkey: r,
    };

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            StarlingTopBar(
              title: 'Friends',
              right: StarlingIconButton(
                onPressed: () => _showInvite(context),
                semanticLabel: 'Add a friend',
                child: const Icon(LucideIcons.plus, size: 20),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  ...inbound.map((r) => _InboundBanner(request: r)),
                  if (inbound.isNotEmpty) const SizedBox(height: 12),
                  _AddFriendCard(onTap: () => _showInvite(context)),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      '${follows.length} friend${follows.length == 1 ? '' : 's'}',
                      style: starling.typography.micro,
                    ),
                  ),
                  if (follows.isEmpty &&
                      outbound.isEmpty &&
                      followersOnly.isEmpty)
                    _EmptyHint()
                  else ...[
                    for (final follow in follows)
                      _FriendRow(
                        follow: follow,
                        acceptPending: _acceptPending(
                          inboundByPubkey[follow.pubkey]?.status,
                        ),
                      ),
                    for (final pending in outbound)
                      _OutboundPendingRow(request: pending),
                    if (followersOnly.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'Follows you',
                          style: starling.typography.micro,
                        ),
                      ),
                      for (final r in followersOnly)
                        _FollowerOnlyRow(request: r),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInvite(BuildContext context) {
    showStarlingSheet(context: context, builder: (_) => const QrInviteSheet());
  }
}

class _InboundBanner extends ConsumerWidget {
  const _InboundBanner({required this.request});
  final FollowRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final shortKey = shortPubkey(request.pubkey);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: starling.colors.sageSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: starling.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: shortKey, color: starling.colors.sage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shortKey, style: starling.typography.body),
                    Text(
                      'wants to follow you',
                      style: starling.typography.micro,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Reject',
                  onPressed: () => _reject(context, ref),
                  block: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: 'Accept',
                  onPressed: () => _accept(context, ref),
                  block: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    try {
      final delivery = await ref
          .read(followServiceProvider)
          .acceptFollowRequest(request.pubkey);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (delivery) {
            AcceptDelivery.delivered => 'Accepted',
            AcceptDelivery.queued => 'Accepted — queued for retry',
            AcceptDelivery.failed => 'Accept failed',
          }),
          duration: const Duration(seconds: 2),
        ),
      );
    } on FollowFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Accept failed: ${e.message}')));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    await ref.read(followServiceProvider).rejectFollowRequest(request.pubkey);
  }
}

class _AddFriendCard extends StatelessWidget {
  const _AddFriendCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Material(
      color: starling.colors.linen,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: starling.colors.hairline),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: starling.colors.sageSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.qrCode,
                  size: 22,
                  color: starling.colors.sageDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add a friend', style: starling.typography.body),
                    const SizedBox(height: 2),
                    Text(
                      'Scan their QR, or share yours.',
                      style: starling.typography.micro,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton(label: 'Open', onPressed: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

/// True when our follow-back accept to this peer is queued but undelivered —
/// i.e. we follow them and they follow us, but our `/follow-accept` hasn't
/// landed yet, so the mutual (and voice) isn't finalized. Driven off the
/// inbound-follower row status.
bool _acceptPending(String? status) =>
    status == 'pending-send' || status == 'send-failed';

class _FriendRow extends ConsumerStatefulWidget {
  const _FriendRow({required this.follow, this.acceptPending = false});
  final Follow follow;

  /// When true, our accept to this friend is still in flight — show a
  /// "Finishing connection…" sub-status + a manual Retry so a stalled
  /// handshake is never silently stuck behind the dedup.
  final bool acceptPending;

  @override
  ConsumerState<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends ConsumerState<_FriendRow> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref
          .read(followServiceProvider)
          .retryQueuedAccepts(
            onlyPubkey: widget.follow.pubkey,
            ignoreBackoff: true,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retrying connection…'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // Best-effort — the inbound-follower stream reflects the real outcome.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final follow = widget.follow;
    final starling = StarlingTheme.of(context);
    final clock = ref.watch(clockProvider);
    final now = clock.nowUnixSeconds();
    final reachable = follow.lastSyncedAt > 0 && now - follow.lastSyncedAt < 60;
    // A friend's name + avatar live in their latest kind=2 profile event, not
    // the `follows` row — resolve them the same way the feed and profile
    // screens do. Fall back to a short pubkey while the profile is loading.
    final profile = ref.watch(followProfileProvider(follow.pubkey));
    final displayName = profile.maybeWhen(
      data: (p) => p.displayName,
      orElse: () => shortPubkey(follow.pubkey),
    );
    final avatarHash = profile.maybeWhen(
      data: (p) => p.avatarHash,
      orElse: () => null,
    );
    final avatarMsgSeq = profile.maybeWhen(
      data: (p) => p.avatarMsgSeq,
      orElse: () => null,
    );

    final String statusText;
    final Color statusColor;
    if (widget.acceptPending) {
      statusText = 'Finishing connection…';
      statusColor = starling.colors.clay;
    } else if (reachable) {
      statusText = '● Reachable';
      statusColor = starling.colors.success;
    } else if (follow.lastSyncedAt > 0) {
      statusText =
          'Last seen ${timeAgo(follow.lastSyncedAt, nowUnixSeconds: now)}';
      statusColor = starling.colors.stone;
    } else {
      statusText = 'Not yet synced';
      statusColor = starling.colors.stone;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: starling.colors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          EncryptedAvatar(
            name: displayName,
            pubkey: follow.pubkey,
            avatarHash: avatarHash,
            avatarMsgSeq: avatarMsgSeq,
            color: avatarColorFor(follow.pubkey, starling.colors),
            size: AvatarSize.md,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: starling.typography.body),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: starling.typography.micro.copyWith(color: statusColor),
                ),
              ],
            ),
          ),
          if (widget.acceptPending) ...[
            SecondaryButton(
              label: _retrying ? 'Retrying…' : 'Retry',
              onPressed: _retrying ? null : _retry,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            const SizedBox(width: 4),
          ],
          StarlingIconButton(
            onPressed: () => showStarlingSheet(
              context: context,
              builder: (_) => FriendActionsSheet(follow: follow),
            ),
            semanticLabel: 'Friend options',
            child: const Icon(LucideIcons.ellipsis, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Row for a peer who follows us but whom we don't follow back. Surfaces
/// the asymmetric handshake state so users can see who has connected to
/// them without having to scan the other direction first.
class _FollowerOnlyRow extends ConsumerStatefulWidget {
  const _FollowerOnlyRow({required this.request});
  final FollowRequest request;

  @override
  ConsumerState<_FollowerOnlyRow> createState() => _FollowerOnlyRowState();
}

class _FollowerOnlyRowState extends ConsumerState<_FollowerOnlyRow> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final shortKey = shortPubkey(widget.request.pubkey);
    final ourOnionReady = ref
        .watch(ownEndpointsProvider)
        .any((e) => e.type == 'onion');
    final statusText = switch (widget.request.status) {
      'accepted' =>
        ourOnionReady ? 'Follows you' : 'Follows you — Tor starting…',
      'pending-send' => 'Follows you — accept queued',
      'send-failed' => 'Follows you — accept undelivered, still retrying',
      _ => 'Follows you',
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: starling.colors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Avatar(name: shortKey, size: AvatarSize.md),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shortKey, style: starling.typography.body),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: starling.typography.micro.copyWith(
                    color: starling.colors.stone,
                  ),
                ),
              ],
            ),
          ),
          PrimaryButton(
            label: _sending ? 'Sending…' : 'Follow back',
            onPressed: (_sending || !ourOnionReady) ? null : _followBack,
          ),
        ],
      ),
    );
  }

  Future<void> _followBack() async {
    setState(() => _sending = true);
    try {
      // PeerReachabilityMonitor.probeCard handles live mDNS resolution
      // inside FollowService now — no caller-side endpoint juggling.
      await ref.read(followServiceProvider).followBack(widget.request.pubkey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow request sent'),
          duration: Duration(seconds: 2),
        ),
      );
    } on FollowFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Follow back failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Follow back failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _OutboundPendingRow extends StatelessWidget {
  const _OutboundPendingRow({required this.request});
  final FollowRequest request;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final shortKey = shortPubkey(request.pubkey);
    final statusLabel = switch (request.status) {
      'pending' => 'Pending',
      'pending-send' => 'Pending — retrying',
      'send-failed' => 'Send failed',
      'accepted' => 'Sent',
      _ => request.status,
    };
    return Opacity(
      opacity: 0.65,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: starling.colors.hairline)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Avatar(name: shortKey, size: AvatarSize.md),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortKey, style: starling.typography.body),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: starling.typography.micro.copyWith(
                      color: starling.colors.stone,
                    ),
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

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(LucideIcons.users, size: 32, color: starling.colors.stone),
          const SizedBox(height: 8),
          Text(
            'No friends yet',
            style: starling.typography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            "Tap 'Add a friend' to scan a QR or share your own.",
            style: starling.typography.small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
