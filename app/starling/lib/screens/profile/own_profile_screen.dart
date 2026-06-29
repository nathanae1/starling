import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../providers/feed_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/identity_provider.dart';
import '../../providers/own_profile_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/encrypted_avatar.dart';
import '../../widgets/encrypted_image.dart';
import '../../widgets/starling_address_row.dart';
import '../../widgets/qr_invite_sheet.dart';
import '../../widgets/sheet.dart';

/// "You" tab root: identity block (avatar/name/bio + Share invite/Edit),
/// counts, and a 3-column post grid. Tapping a cell pushes the detail
/// inside the You branch's stack so back returns to "You", not Feed.
class OwnProfileScreen extends ConsumerWidget {
  const OwnProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final profileAsync = ref.watch(ownProfileProvider);
    final followsAsync = ref.watch(followsProvider);
    final postsAsync = ref.watch(ownPostsProvider);

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: profileAsync.when(
                data: (profile) {
                  final pubkey = ref
                      .watch(identityControllerProvider)
                      .value
                      ?.pubkey;
                  return _IdentityBlock(profile: profile, pubkey: pubkey);
                },
                loading: () => const _IdentityBlockSkeleton(),
                error: (e, _) => _ErrorBlock(message: '$e'),
              ),
            ),
            SliverToBoxAdapter(
              child: _StatsRow(
                friendsCount: followsAsync.maybeWhen(
                  data: (f) => f.length,
                  orElse: () => 0,
                ),
                postsCount: postsAsync.maybeWhen(
                  data: (p) => p.length,
                  orElse: () => 0,
                ),
              ),
            ),
            postsAsync.when(
              data: (events) => _PostGrid(events: events, ownTab: true),
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) =>
                  SliverToBoxAdapter(child: _ErrorBlock(message: '$e')),
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
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You',
              style: starling.typography.h2.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          StarlingIconButton(
            onPressed: () => context.push('/settings'),
            semanticLabel: 'Settings',
            child: const Icon(LucideIcons.settings, size: 20),
          ),
        ],
      ),
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.profile, required this.pubkey});

  final OwnProfileSnapshot profile;
  final String? pubkey;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        children: [
          EncryptedAvatar(
            name: profile.displayName,
            pubkey: pubkey ?? '',
            avatarHash: profile.avatarHash,
            avatarMsgSeq: profile.avatarMsgSeq,
            color: starling.colors.clay,
            size: AvatarSize.lg,
          ),
          const SizedBox(height: 14),
          Text(
            profile.displayName,
            style: starling.typography.h2.copyWith(
              fontSize: 24,
              letterSpacing: -0.24,
            ),
            textAlign: TextAlign.center,
          ),
          if (pubkey != null) ...[
            const SizedBox(height: 6),
            StarlingAddressRow(pubkey: pubkey!),
          ],
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
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SecondaryButton(
                label: 'Share invite',
                leading: const Icon(LucideIcons.qrCode, size: 16),
                onPressed: () => showStarlingSheet(
                  context: context,
                  builder: (_) => const QrInviteSheet(),
                ),
              ),
              const SizedBox(width: 12),
              SecondaryButton(
                label: 'Edit',
                leading: const Icon(LucideIcons.pencil, size: 16),
                onPressed: () => context.push('/profile/edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Muted placeholder shown while the profile snapshot loads, so the identity
/// area holds its shape with a skeleton instead of a blank gap.
class _IdentityBlockSkeleton extends StatelessWidget {
  const _IdentityBlockSkeleton();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final muted = starling.colors.hairline;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        children: [
          // lg avatar diameter.
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: muted, shape: BoxShape.circle),
          ),
          const SizedBox(height: 14),
          bar(150, 20), // name
          const SizedBox(height: 10),
          bar(180, 13), // address
          const SizedBox(height: 10),
          bar(160, 13), // bio
          const SizedBox(height: 18),
          bar(220, 36), // action row
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.friendsCount, required this.postsCount});

  final int friendsCount;
  final int postsCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StatCell(label: 'friends', value: friendsCount),
          const SizedBox(width: 32),
          _StatCell(label: 'posts', value: postsCount),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: starling.typography.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: starling.colors.ink,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: starling.typography.caption),
      ],
    );
  }
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.events, required this.ownTab});

  final List<Event> events;
  final bool ownTab;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final routePrefix = ownTab ? '/you' : '/feed';
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final event = events[index];
          final hash = event.media.isNotEmpty ? event.media.first.hash : null;
          return GestureDetector(
            onTap: () => context.push('$routePrefix/post/${event.id}'),
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

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: starling.typography.small.copyWith(
          color: starling.colors.danger,
        ),
      ),
    );
  }
}
