import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/follow_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/types.dart';
import '../../theme/starling_theme.dart';

class FriendActionsSheet extends ConsumerWidget {
  const FriendActionsSheet({super.key, required this.follow});

  final Follow follow;

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
            follow.displayName ??
                (follow.pubkey.length > 8
                    ? follow.pubkey.substring(0, 8)
                    : follow.pubkey),
            style: starling.typography.h3,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        _ActionRow(
          icon: LucideIcons.user,
          label: 'View profile',
          onTap: () {
            Navigator.of(context).pop();
            context.push('/friends/profile/${follow.pubkey}');
          },
        ),
        _ActionRow(
          icon: LucideIcons.userMinus,
          label: 'Unfollow',
          destructive: true,
          onTap: () => _confirmUnfollow(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmUnfollow(BuildContext context, WidgetRef ref) async {
    final isAlsoFollower = await ref
        .read(storageServiceProvider)
        .isAcceptedFollower(follow.pubkey);
    if (!context.mounted) return;
    final name = follow.displayName ?? 'this friend';
    final body = isAlsoFollower
        ? 'You will stop receiving posts from $name, and they will no '
              'longer receive your future posts.'
        : 'You will stop receiving posts from $name.';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
        );
      },
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    await ref.read(followServiceProvider).unfollow(follow.pubkey);
    if (context.mounted) Navigator.of(context).pop();
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
