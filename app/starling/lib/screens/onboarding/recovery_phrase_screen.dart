import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

class RecoveryPhraseScreen extends ConsumerStatefulWidget {
  const RecoveryPhraseScreen({super.key});

  @override
  ConsumerState<RecoveryPhraseScreen> createState() =>
      _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends ConsumerState<RecoveryPhraseScreen> {
  bool _copied = false;

  // Gates the continue button. One unguarded tap here used to clear the
  // phrase forever — it's viewable nowhere else in the app.
  bool _confirmed = false;

  Future<void> _copy(String joined) async {
    await Clipboard.setData(ClipboardData(text: joined));
    if (!mounted) return;
    final starling = StarlingTheme.of(context);
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: starling.colors.ink,
          duration: const Duration(seconds: 2),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.check, size: 16, color: starling.colors.paper),
              const SizedBox(width: 8),
              Text(
                'Copied to clipboard',
                style: starling.typography.small.copyWith(
                  color: starling.colors.paper,
                ),
              ),
            ],
          ),
        ),
      );
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
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
                      // Safety warning — a prominent alert above the phrase so
                      // it's read before the words, not as fine print below.
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: starling.colors.sageSoft,
                          border: Border.all(color: starling.colors.sageDeep),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              LucideIcons.shieldAlert,
                              size: 20,
                              color: starling.colors.sageDeep,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Write this down and keep it offline. It's the "
                                'only way to recover your account — no server '
                                "knows who you are. Don't screenshot it or "
                                'share it with anyone.',
                                style: starling.typography.small.copyWith(
                                  color: starling.colors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PhraseCard(phrase: phrase),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => _copy(phrase.join(' ')),
                        style: TextButton.styleFrom(
                          foregroundColor: starling.colors.sageDeep,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: Text(
                          _copied ? 'Copied' : 'Copy to clipboard',
                          style: starling.typography.caption.copyWith(
                            color: starling.colors.sageDeep,
                            decoration: TextDecoration.underline,
                            decorationColor: starling.colors.sageDeep,
                          ),
                        ),
                      ),
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

/// Bordered, two-column display of the 24-word recovery phrase. Words run
/// down each column (1–12 on the left, 13–24 on the right), each clearly
/// numbered and set in a larger monospace face so they're easy to scan and
/// verify against a written copy. A hairline divider keeps the columns
/// visually distinct.
class _PhraseCard extends StatelessWidget {
  const _PhraseCard({required this.phrase});

  final List<String> phrase;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final half = (phrase.length / 2).ceil();

    Widget column(int start, int end) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = start; i < end; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == end - 1 ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.right,
                      style: starling.typography.monoSmall.copyWith(
                        color: starling.colors.stone,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      phrase[i],
                      style: starling.typography.mono.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: starling.colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: starling.colors.linen,
        border: Border.all(color: starling.colors.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column(0, half)),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: starling.colors.hairline,
            ),
            Expanded(child: column(half, phrase.length)),
          ],
        ),
      ),
    );
  }
}
