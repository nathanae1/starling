import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';
import 'buttons.dart';
import 'starling_icon.dart';
import 'qr_invite_sheet.dart';
import 'sheet.dart';

/// Empty feed state — shown when the user has no follows and no own posts.
/// The CTA opens the share-invite sheet.
class EmptyFeed extends StatelessWidget {
  const EmptyFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a friend to get started',
            textAlign: TextAlign.center,
            style: starling.typography.h2,
          ),
          const SizedBox(height: 8),
          Text(
            'Starling is a private space for the people you choose. Share your '
            "invite — there's no other way for someone to find you here.",
            textAlign: TextAlign.center,
            style: starling.typography.small,
          ),
          const SizedBox(height: 32),
          _InviteCard(),
          const SizedBox(height: 12),
          // Secondary nudge — invite stays the primary action, but they can
          // also seed their feed so there's something waiting when a friend
          // accepts.
          Center(
            child: GhostButton(
              label: 'Or share your first post',
              onPressed: () => context.push('/compose'),
            ),
          ),
        ],
      ),
    );
  }
}

void _openInviteSheet(BuildContext context) {
  showStarlingSheet(context: context, builder: (_) => const QrInviteSheet());
}

class _InviteCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Material(
      color: starling.colors.linen,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openInviteSheet(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: starling.colors.hairline),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(18),
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
                child: StarlingIcon(
                  LucideIcons.qrCode,
                  size: 22,
                  color: starling.colors.sageDeep,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share your invite',
                      style: starling.typography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scan their QR, or send them yours.',
                      style: starling.typography.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton(
                label: 'Open',
                onPressed: () => _openInviteSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
