import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _controller = TextEditingController();
  bool _restoring = false;
  String? _error;

  List<String> get _words => _controller.text
      .split(RegExp(r'\s+'))
      .map((w) => w.trim().toLowerCase())
      .where((w) => w.isNotEmpty)
      .toList();

  bool get _canRestore => _words.length == 24 && !_restoring;

  Future<void> _onRestore() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      await ref
          .read(onboardingControllerProvider.notifier)
          .restoreIdentity(_words);
      if (!mounted) return;
      context.go('/onboarding/done');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('unknown word')) {
      return "That doesn't look like a valid recovery phrase. One of the words isn't in the word list.";
    }
    if (msg.contains('checksum')) {
      return "That phrase doesn't match — check for typos or a missing word.";
    }
    if (msg.contains('24 words')) {
      return 'Your recovery phrase is 24 words. You\'ve entered ${_words.length}.';
    }
    return 'Could not restore: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarlingIconButton(
                onPressed: () => context.go('/onboarding/welcome'),
                semanticLabel: 'Back',
                child: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
              const SizedBox(height: 18),
              Text(
                'Restore from\nrecovery phrase',
                style: starling.typography.h1.copyWith(
                  fontSize: 28,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Paste or type your 24 words, separated by spaces. Your friends '
                "and posts won't come back — there's nothing to restore from "
                'the network — but your account will.',
                style: starling.typography.small,
              ),
              const SizedBox(height: 22),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  // Secret words: don't let the OS mangle them (autocorrect,
                  // smart quotes/dashes) or learn them (suggestions feed the
                  // keyboard's personal dictionary).
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textCapitalization: TextCapitalization.none,
                  // Clear a stale validation error as soon as the user edits,
                  // so the word-count progress takes the slot back while typing.
                  onChanged: (_) => setState(() => _error = null),
                  style: starling.typography.mono,
                  cursorColor: starling.colors.sage,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: starling.colors.linen,
                    hintText:
                        'river candle slow paper linen starling morning kettle ...',
                    hintStyle: starling.typography.mono.copyWith(
                      color: starling.colors.stone,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: starling.colors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: starling.colors.sage,
                        width: 2,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: starling.colors.hairline),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Validation error and word-count progress are kept in separate
              // visual treatments so they don't compete: the error is a
              // danger-tinted pill, shown only when a restore attempt failed;
              // otherwise the quiet progress caption holds the slot.
              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: starling.colors.danger.withValues(alpha: 0.10),
                    border: Border.all(
                      color: starling.colors.danger.withValues(alpha: 0.45),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.triangleAlert,
                        size: 16,
                        color: starling.colors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: starling.typography.small.copyWith(
                            color: starling.colors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '${_words.length} / 24 words',
                  style: starling.typography.caption.copyWith(
                    color: starling.colors.stone,
                  ),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _restoring ? 'Restoring…' : 'Restore',
                block: true,
                leading: _restoring ? const ButtonSpinner() : null,
                onPressed: _canRestore ? _onRestore : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
