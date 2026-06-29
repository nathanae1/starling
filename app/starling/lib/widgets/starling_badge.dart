import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

/// A small status pill: a tinted background with either a leading dot or a
/// glyph, plus a label. Consolidates the inline status chips repeated across
/// connection/network settings and friend reachability so status vocabulary
/// and styling stay consistent.
class StarlingBadge extends StatelessWidget {
  const StarlingBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;

  /// Optional leading glyph. When null, a small filled dot is shown instead.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: starling.typography.micro.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
