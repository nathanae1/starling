import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';
import 'buttons.dart';

/// Shows a themed confirmation dialog and resolves to `true` when confirmed,
/// `false` when cancelled or dismissed. Replaces the default Material
/// `AlertDialog` (white background, blue buttons) so confirmations match the
/// Starling theme. Use [destructive] for delete/clear actions to render the
/// confirm button in the accent (clay) color.
Future<bool> showStarlingConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _StarlingAlertDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _StarlingAlertDialog extends StatelessWidget {
  const _StarlingAlertDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Dialog(
      backgroundColor: starling.colors.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: starling.typography.h3.copyWith(
                fontFamily: 'Fraunces',
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: starling.typography.small.copyWith(
                color: starling.colors.graphite,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: cancelLabel,
                    block: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: destructive
                      ? AccentButton(
                          label: confirmLabel,
                          block: true,
                          onPressed: () => Navigator.of(context).pop(true),
                        )
                      : PrimaryButton(
                          label: confirmLabel,
                          block: true,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
