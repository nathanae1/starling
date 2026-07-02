import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../providers/feed_provider.dart';
import '../../providers/follow_profile_provider.dart';
import '../../providers/follow_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/minute_ticker_provider.dart';
import '../../providers/service_providers.dart';
import '../../sync/peer_reachability_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/time_ago.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/encrypted_avatar.dart';
import '../../widgets/encrypted_image.dart';
import '../../widgets/starling_address_row.dart';

/// Other-profile screen: header + last-synced + reachability pill, post grid,
/// unfollow CTA wired to [FollowService].
class OtherProfileScreen extends ConsumerWidget {
  const OtherProfileScreen({super.key, required this.pubkey});

  final String pubkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final profileAsync = ref.watch(followProfileProvider(pubkey));
    final postsAsync = ref.watch(profilePostsProvider(pubkey));
    final followsAsync = ref.watch(followsProvider);

    final lastSyncedAt = followsAsync.maybeWhen(
      data: (list) {
        for (final f in list) {
          if (f.pubkey == pubkey) return f.lastSyncedAt;
        }
        return 0;
      },
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: profileAsync.when(
                data: (p) => _IdentityBlock(
                  profile: p,
                  pubkey: pubkey,
                  lastSyncedAt: lastSyncedAt,
                ),
                loading: () => const SizedBox(height: 200),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    friendlyError(e, tag: 'profile'),
                    style: starling.typography.small.copyWith(
                      color: starling.colors.danger,
                    ),
                  ),
                ),
              ),
            ),
            postsAsync.when(
              data: (events) => _PostGrid(events: events),
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    friendlyError(e, tag: 'profile'),
                    style: starling.typography.small.copyWith(
                      color: starling.colors.danger,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          StarlingIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: 'Back',
            child: const Icon(LucideIcons.arrowLeft, size: 20),
          ),
        ],
      ),
    );
  }
}

class _IdentityBlock extends ConsumerWidget {
  const _IdentityBlock({
    required this.profile,
    required this.pubkey,
    required this.lastSyncedAt,
  });

  final FollowProfileSnapshot profile;
  final String pubkey;
  final int lastSyncedAt;

  String get displayName => profile.displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final now = ref.watch(clockProvider).nowUnixSeconds();
    // Re-render each minute so the last-seen labels stay honest.
    ref.watch(minuteTickerProvider);
    // Live per-transport reachability (LAN + Tor + libp2p), not the stale
    // "synced within the last minute" heuristic.
    final reachability =
        ref.watch(peerReachabilityStateProvider).value ?? const {};
    final reachable = reachability[pubkey]?.isReachable ?? false;
    final statusText = reachable
        ? '● Reachable'
        : lastSyncedAt > 0
        ? 'Last seen ${timeAgo(lastSyncedAt, nowUnixSeconds: now)}'
        : 'Not yet synced';
    final statusColor = reachable
        ? starling.colors.success
        : starling.colors.stone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          EncryptedAvatar(
            name: displayName,
            pubkey: pubkey,
            avatarHash: profile.avatarHash,
            avatarMsgSeq: profile.avatarMsgSeq,
            size: AvatarSize.lg,
          ),
          const SizedBox(height: 14),
          Text(
            displayName,
            style: starling.typography.h2.copyWith(
              fontSize: 24,
              letterSpacing: -0.24,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          StarlingAddressRow(pubkey: pubkey),
          if (profile.bio != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                profile.bio!,
                textAlign: TextAlign.center,
                style: starling.typography.small,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            statusText,
            style: starling.typography.small.copyWith(color: statusColor),
          ),
          if (lastSyncedAt > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Last synced ${timeAgo(lastSyncedAt, nowUnixSeconds: now)}',
              style: starling.typography.micro,
            ),
          ],
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Unfollow',
            onPressed: () => _confirmUnfollow(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnfollow(BuildContext context, WidgetRef ref) async {
    final isAlsoFollower = await ref
        .read(storageServiceProvider)
        .isAcceptedFollower(pubkey);
    if (!context.mounted) return;
    final body = isAlsoFollower
        ? 'You will stop receiving posts from $displayName, and they '
              'will no longer receive your future posts.'
        : 'You will stop receiving posts from $displayName.';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unfollow?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    await ref.read(followServiceProvider).unfollow(pubkey);
    if (context.mounted) unawaited(Navigator.of(context).maybePop());
  }
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.events});
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final event = events[index];
          final hash = event.media.isNotEmpty ? event.media.first.hash : null;
          return GestureDetector(
            onTap: () => context.push('/feed/post/${event.id}'),
            child: hash == null
                ? const ColoredBox(color: Colors.transparent)
                : EncryptedImage(
                    hash: hash,
                    pubkey: event.pubkey,
                    msgSeq: event.msgSeq,
                  ),
          );
        }, childCount: events.length),
      ),
    );
  }
}
