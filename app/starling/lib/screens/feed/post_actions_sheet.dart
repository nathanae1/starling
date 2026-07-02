import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/events_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/post_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/starling_alert_dialog.dart';

class PostActionsSheet extends ConsumerWidget {
  const PostActionsSheet({super.key, required this.eventId, this.onDeleted});

  final String eventId;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Post',
            style: starling.typography.h3,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        _ActionRow(
          icon: LucideIcons.trash,
          label: 'Delete post',
          destructive: true,
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showStarlingConfirm(
      context,
      title: 'Delete post?',
      message:
          'Followers will stop seeing this post the next time they sync. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirm || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await runWithStarlingProgress(
        context,
        message: 'Deleting…',
        op: () => ref.read(postServiceProvider).deletePost(eventId),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, tag: 'delete_post'))),
      );
      return;
    }
    ref.invalidate(feedProvider);
    ref.invalidate(ownPostsProvider);
    ref.invalidate(ownEventsProvider);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    onDeleted?.call();
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final color = destructive ? starling.colors.danger : starling.colors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: starling.typography.body.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
