import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/secure_screen.dart';
import '../../widgets/buttons.dart';
import '../../widgets/phrase_card.dart';

class RecoveryPhraseScreen extends ConsumerStatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  ConsumerState<RecoveryPhraseScreen> createState() =>
      _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends ConsumerState<RecoveryPhraseScreen> {
  // Gates the continue button. One unguarded tap here used to clear the
  // phrase forever — it's viewable nowhere else in the app.
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    // The copy says "don't screenshot it" — enforce it where the OS lets us
    // (Android FLAG_SECURE; no-op on iOS).
    SecureScreen.enable();
  }

  @override
  void dispose() {
    SecureScreen.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final session = ref.watch(onboardingControllerProvider);
    final phrase = session.recoveryPhrase ?? const <String>[];

    if (phrase.isEmpty) {
      // Shouldn't happen — recovery phrase is set when createIdentity runs.
      // If we landed here with no phrase, bounce back to welcome.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/onboarding/welcome');
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your recovery phrase',
                        style: starling.typography.h1.copyWith(
                          fontSize: 28,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const PhraseWarning(),
                      const SizedBox(height: 20),
                      PhraseCard(phrase: phrase),
                      const SizedBox(height: 10),
                      PhraseCopyButton(phrase: phrase),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Checkbox confirm (no spot-check quiz in v1) — makes clearing
              // the phrase a deliberate two-step act instead of one tap.
              InkWell(
                onTap: () => setState(() => _confirmed = !_confirmed),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _confirmed,
                        onChanged: (v) =>
                            setState(() => _confirmed = v ?? false),
                        activeColor: starling.colors.sageDeep,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "I've written these 24 words down somewhere safe",
                          style: starling.typography.small.copyWith(
                            color: starling.colors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'I wrote it down',
                block: true,
                onPressed: _confirmed
                    ? () {
                        ref
                            .read(onboardingControllerProvider.notifier)
                            .clearRecoveryPhrase();
                        context.go('/onboarding/done');
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
