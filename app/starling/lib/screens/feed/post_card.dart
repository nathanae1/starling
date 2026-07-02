import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../providers/comments_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/follow_profile_provider.dart';
import '../../providers/identity_provider.dart';
import '../../providers/minute_ticker_provider.dart';
import '../../providers/reactions_provider.dart';
import '../../providers/service_providers.dart';
import '../../theme/starling_theme.dart';
import '../../utils/pubkey_format.dart';
import '../../utils/time_ago.dart';
import '../../widgets/avatar.dart';
import '../../widgets/encrypted_avatar.dart';
import '../../widgets/encrypted_image.dart';
import '../../widgets/starling_icon.dart';
import '../../widgets/reaction_button.dart';
import '../../widgets/sheet.dart';
import 'post_actions_sheet.dart';

/// A single post in the chronological feed. Plan 06 ships static heart and
/// comment counts (both 0); Plan 10 wires the real toggles.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.event, required this.onTap});

  final Event event;
  final VoidCallback onTap;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  @override
  void initState() {
    super.initState();
    // Marking happens once, when the card is first constructed — not on
    // every rebuild. `ListView.builder` only builds items near the
    // viewport, so first construction still means "seen near viewport",
    // which is good enough for the retention grace period.
    ref.read(lastViewedTrackerProvider).markViewed(widget.event.id);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final starling = StarlingTheme.of(context);
    final profile = ref.watch(followProfileProvider(event.pubkey));
    final clock = ref.watch(clockProvider);
    // Re-render each minute so the relative timestamp stays honest.
    ref.watch(minuteTickerProvider);
    final isOwnPost =
        ref.watch(identityControllerProvider).value?.pubkey == event.pubkey;
    final caption = event.content.isEmpty
        ? ''
        : utf8.decode(event.content, allowMalformed: true);
    final mediaHash = event.media.isNotEmpty ? event.media.first.hash : null;

    final displayName = profile.maybeWhen(
      data: (p) => firstNameOf(p.displayName),
      orElse: () => 'Friend',
    );
    final avatarHash = profile.maybeWhen(
      data: (p) => p.avatarHash,
      orElse: () => null,
    );
    final avatarMsgSeq = profile.maybeWhen(
      data: (p) => p.avatarMsgSeq,
      orElse: () => null,
    );

    return Semantics(
      // The whole-card tap opens the post detail; without a label the
      // gesture exists but a screen reader announces nothing about it.
      button: true,
      label: 'Post by $displayName',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    // Avatar + name open the author's profile. The nested
                    // GestureDetector wins the tap over the whole-card
                    // handler, which still routes to the post detail.
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            context.push('/feed/profile/${event.pubkey}'),
                        child: Row(
                          children: [
                            _AuthorAvatar(
                              pubkey: event.pubkey,
                              name: displayName,
                              avatarHash: avatarHash,
                              avatarMsgSeq: avatarMsgSeq,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                displayName,
                                style: starling.typography.small.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: starling.colors.ink,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      timeAgo(
                        event.createdAt,
                        nowUnixSeconds: clock.nowUnixSeconds(),
                      ),
                      style: starling.typography.micro,
                    ),
                    if (isOwnPost) ...[
                      const SizedBox(width: 4),
                      _OverflowButton(eventId: event.id),
                    ],
                  ],
                ),
              ),
              // Photo: full-bleed 4:5 with hairline top/bottom; no radii.
              if (mediaHash != null)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: starling.colors.hairline),
                      bottom: BorderSide(color: starling.colors.hairline),
                    ),
                  ),
                  child: EncryptedImage(
                    hash: mediaHash,
                    pubkey: event.pubkey,
                    msgSeq: event.msgSeq,
                    aspectRatio: 4 / 5,
                  ),
                ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ClampedCaption(
                    caption: caption,
                    onMore: widget.onTap,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _CardActionRow(
                  eventId: event.id,
                  onComment: widget.onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feed captions clamp to a few lines with a "more" affordance that opens
/// the post detail — a long caption shouldn't push the next photo off
/// screen.
class _ClampedCaption extends StatelessWidget {
  const _ClampedCaption({required this.caption, this.onMore});

  static const int _maxLines = 4;

  final String caption;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final style = starling.typography.body.copyWith(fontSize: 15, height: 1.5);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: caption, style: style),
          maxLines: _maxLines,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption,
              style: style,
              maxLines: _maxLines,
              overflow: TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: onMore,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'more',
                    style: starling.typography.small.copyWith(
                      color: starling.colors.stone,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OverflowButton extends StatelessWidget {
  const _OverflowButton({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Semantics(
      button: true,
      label: 'Post options',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showStarlingSheet(
          context: context,
          builder: (_) => PostActionsSheet(eventId: eventId),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: StarlingIcon(
            LucideIcons.ellipsis,
            size: 18,
            color: starling.colors.graphite,
          ),
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.pubkey,
    required this.name,
    required this.avatarHash,
    required this.avatarMsgSeq,
  });

  final String pubkey;
  final String name;
  final String? avatarHash;
  final int? avatarMsgSeq;

  @override
  Widget build(BuildContext context) {
    // Hash-derived color for the initials fallback (no avatar set / still
    // decrypting), so each friend has a stable, distinct circle.
    final colors = StarlingTheme.of(context).colors;
    return EncryptedAvatar(
      name: name,
      pubkey: pubkey,
      avatarHash: avatarHash,
      avatarMsgSeq: avatarMsgSeq,
      color: avatarColorFor(pubkey, colors),
      size: AvatarSize.sm,
    );
  }
}

class _CardActionRow extends ConsumerWidget {
  const _CardActionRow({required this.eventId, required this.onComment});

  final String eventId;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final reactionsAsync = ref.watch(reactionsProvider(eventId));
    final commentsAsync = ref.watch(commentsProvider(eventId));

    final summary = reactionsAsync.maybeWhen(
      data: (s) => s,
      orElse: () => const ReactionSummary(count: 0, likedByMe: false),
    );
    final commentCount = commentsAsync.maybeWhen(
      data: (c) => c.length,
      orElse: () => 0,
    );

    return Row(
      children: [
        ReactionButton(
          liked: summary.likedByMe,
          count: summary.count,
          compact: true,
          onTap: () =>
              ref.read(reactionControllerProvider(eventId).notifier).toggle(),
        ),
        const SizedBox(width: 18),
        Semantics(
          button: true,
          label: 'Comments',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onComment,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  StarlingIcon(
                    LucideIcons.messageCircle,
                    size: 22,
                    color: starling.colors.graphite,
                  ),
                  if (commentCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('$commentCount', style: starling.typography.small),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
