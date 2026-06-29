import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

/// A bottom-pinned action bar: paper background, hairline top border, and a
/// bottom `SafeArea` so it clears the home indicator. Holds whatever [child]
/// row of buttons a screen supplies, giving Compose and Preview one shared
/// footer treatment.
///
/// Place it as the **last child of a resizing `Column`** (it then floats just
/// above the keyboard via the scaffold's default `resizeToAvoidBottomInset`),
/// or inside a `Positioned(bottom: 0)` for scroll-over-content layouts that
/// have no text field.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: starling.colors.paper,
        border: Border(top: BorderSide(color: starling.colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }
}
