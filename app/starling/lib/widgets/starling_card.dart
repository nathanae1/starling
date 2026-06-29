import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

/// A titled surface card: paper background, hairline border, rounded corners,
/// optional soft shadow. Replaces the ad-hoc `Container` + `BoxDecoration`
/// card pattern repeated across settings/profile screens (e.g. the private
/// `_SectionCard` in network settings) so cards share one treatment.
class StarlingCard extends StatelessWidget {
  const StarlingCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.elevated = false,
  });

  /// Optional uppercase section title rendered above [child].
  final String? title;

  /// Optional leading glyph shown next to [title].
  final IconData? icon;

  final Widget child;
  final EdgeInsets padding;

  /// When true, adds the theme's soft shadow for a lifted surface.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: starling.colors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: starling.colors.hairline),
        boxShadow: elevated ? starling.colors.shadowSoft : null,
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: starling.colors.graphite),
                  const SizedBox(width: 8),
                ],
                Text(title!, style: starling.typography.micro),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}
