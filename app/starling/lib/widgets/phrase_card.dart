import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';

/// Bordered, two-column display of the 24-word recovery phrase. Words run
/// down each column (1–12 on the left, 13–24 on the right), each clearly
/// numbered and set in a larger monospace face so they're easy to scan and
/// verify against a written copy. A hairline divider keeps the columns
/// visually distinct. Shared by onboarding and the settings re-display.
class PhraseCard extends StatelessWidget {
  const PhraseCard({super.key, required this.phrase});

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

/// "Copy to clipboard" for the recovery phrase, with auto-clear: the
/// clipboard is wiped [clearAfter] after the copy — but only if it still
/// holds the phrase, so something else the user copied since isn't stomped —
/// and the snackbar says so up front.
class PhraseCopyButton extends StatefulWidget {
  const PhraseCopyButton({
    super.key,
    required this.phrase,
    this.clearAfter = const Duration(seconds: 60),
  });

  final List<String> phrase;
  final Duration clearAfter;

  @override
  State<PhraseCopyButton> createState() => _PhraseCopyButtonState();
}

class _PhraseCopyButtonState extends State<PhraseCopyButton> {
  static const _snackbarDuration = Duration(seconds: 2);
  bool _copied = false;
  Timer? _clearTimer;
  Timer? _labelTimer;

  @override
  void dispose() {
    _clearTimer?.cancel();
    _labelTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final joined = widget.phrase.join(' ');
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
          duration: _snackbarDuration,
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.check, size: 16, color: starling.colors.paper),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copied — clears in ${widget.clearAfter.inSeconds} seconds',
                  style: starling.typography.small.copyWith(
                    color: starling.colors.paper,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    // Label resets in step with the snackbar (they used to race: 1.4s
    // label vs 2s snackbar).
    _labelTimer?.cancel();
    _labelTimer = Timer(_snackbarDuration, () {
      if (mounted) setState(() => _copied = false);
    });
    _clearTimer?.cancel();
    _clearTimer = Timer(widget.clearAfter, () => _clearClipboard(joined));
  }

  Future<void> _clearClipboard(String expected) async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == expected) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return TextButton(
      onPressed: _copy,
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
    );
  }
}

/// The safety warning shown above the phrase — read before the words, not
/// as fine print below.
class PhraseWarning extends StatelessWidget {
  const PhraseWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
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
              "Write this down and keep it offline. It's the only way to "
              'recover your account — no server knows who you are. '
              "Don't screenshot it or share it with anyone.",
              style: starling.typography.small.copyWith(
                color: starling.colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
