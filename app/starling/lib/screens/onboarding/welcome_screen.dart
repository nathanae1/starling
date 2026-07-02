import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: starling.colors.sageSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'S',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        color: starling.colors.sageDeep,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Starling',
                    style: starling.typography.h2.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Text.rich (not RichText) so the headline honors system font
              // scaling.
              Text.rich(
                TextSpan(
                  style: starling.typography.displayLarge,
                  children: [
                    const TextSpan(text: 'A social feed\nfor your '),
                    TextSpan(
                      text: 'real',
                      style: starling.typography.displayLarge.copyWith(
                        fontStyle: FontStyle.italic,
                        color: starling.colors.sageDeep,
                      ),
                    ),
                    const TextSpan(text: ' friends.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  "No ads. No algorithm. You own everything. Your posts live on your phone, not a company's server.",
                  style: starling.typography.body.copyWith(
                    color: starling.colors.graphite,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              PrimaryButton(
                label: 'Get started',
                block: true,
                // push (not go): Android system back returns here instead
                // of exiting the app mid-onboarding.
                onPressed: () => context.push('/onboarding/setup'),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/onboarding/restore'),
                  style: TextButton.styleFrom(
                    foregroundColor: starling.colors.sageDeep,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: starling.typography.caption.copyWith(
                        color: starling.colors.stone,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Restore from recovery phrase',
                          style: starling.typography.caption.copyWith(
                            color: starling.colors.sageDeep,
                            decoration: TextDecoration.underline,
                            decorationColor: starling.colors.sageDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
