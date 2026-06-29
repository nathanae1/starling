import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';
import '../utils/starling_address.dart';

/// Compact, tappable display of a peer's stable `starling://<pubkey>`
/// address. Tap copies the full address to the clipboard. Shown on
/// profile screens and anywhere else the user-visible identity needs to
/// be surfaced.
class StarlingAddressRow extends StatelessWidget {
  const StarlingAddressRow({
    super.key,
    required this.pubkey,
    this.alignment = MainAxisAlignment.center,
  });

  final String pubkey;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final full = starlingAddressOf(pubkey);
    final short = shortStarlingAddress(pubkey);
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: full));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address copied'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: alignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              short,
              style: starling.typography.small.copyWith(
                color: starling.colors.graphite,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.copy, size: 14, color: starling.colors.stone),
          ],
        ),
      ),
    );
  }
}
