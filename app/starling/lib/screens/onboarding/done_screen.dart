import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

/// Onboarding capstone shown once an identity exists (new account or restore),
/// before dropping into the feed. Purely presentational — reads no providers.
/// The router exempts `/onboarding/done` from the "has identity → /feed"
/// redirect so this screen actually renders instead of being bounced.
class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final colors = starling.colors;

    return Scaffold(
      backgroundColor: colors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.sageSoft,
                    border: Border.all(color: colors.sageDeep, width: 2),
                  ),
                  child: Icon(
                    LucideIcons.check,
                    size: 44,
                    color: colors.sageDeep,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "You're all set",
                textAlign: TextAlign.center,
                style: starling.typography.h1.copyWith(
                  fontSize: 28,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account lives on this device and nowhere else. Add a '
                'friend to start sharing — every post stays end-to-end '
                'encrypted.',
                textAlign: TextAlign.center,
                style: starling.typography.small.copyWith(color: colors.stone),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Go to feed',
                block: true,
                onPressed: () => context.go('/feed'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
