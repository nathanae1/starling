import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/comments_provider.dart';
import '../providers/follow_profile_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/minute_ticker_provider.dart';
import '../providers/service_providers.dart';
import '../theme/starling_theme.dart';
import '../utils/friendly_error.dart';
import '../utils/time_ago.dart';
import 'avatar.dart';

/// Vertical list of comments on a post. Avatar + first name + relative
/// timestamp on top, body underneath. Filtered to follows + self by the
/// underlying [commentsProvider]; non-followed authors' comments are
/// stored but hidden.
class CommentList extends ConsumerWidget {
  const CommentList({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final commentsAsync = ref.watch(commentsProvider(postId));

    return commentsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          friendlyError(e, tag: 'comments'),
          style: starling.typography.small.copyWith(
            color: starling.colors.danger,
          ),
        ),
      ),
      data: (comments) {
        if (comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: Text(
                'No comments yet.',
                style: starling.typography.small.copyWith(
                  color: starling.colors.stone,
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final comment in comments) _CommentRow(comment: comment),
          ],
        );
      },
    );
  }
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({required this.comment});

  final Event comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final clock = ref.watch(clockProvider);
    // Re-render each minute so the relative timestamp stays honest.
    ref.watch(minuteTickerProvider);
    final profile = ref.watch(followProfileProvider(comment.pubkey));
    // "You" only when it's actually the user's comment — a friend's
    // still-loading profile must not fall back to "You".
    final ownPubkey = ref.watch(identityControllerProvider).value?.pubkey;
    final displayName = comment.pubkey == ownPubkey
        ? 'You'
        : profile.maybeWhen(
            data: (p) => firstNameOf(p.displayName),
            orElse: () => 'Friend',
          );
    final body = utf8.decode(comment.content, allowMalformed: true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(name: displayName, size: AvatarSize.sm),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: starling.typography.small.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: starling.colors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(
                        comment.createdAt,
                        nowUnixSeconds: clock.nowUnixSeconds(),
                      ),
                      style: starling.typography.micro,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: starling.typography.body.copyWith(
                    fontSize: 14,
                    color: starling.colors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
