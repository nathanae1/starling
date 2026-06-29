import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

enum AvatarSize { xs, sm, md, lg, xl }

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.color,
    this.size = AvatarSize.md,
    this.imageProvider,
  });

  final String name;
  final Color? color;
  final AvatarSize size;
  final ImageProvider? imageProvider;

  double get _diameter => switch (size) {
    AvatarSize.xs => 20,
    AvatarSize.sm => 28,
    AvatarSize.md => 36,
    AvatarSize.lg => 72,
    AvatarSize.xl => 96,
  };

  double get _fontSize => switch (size) {
    AvatarSize.xs => 10,
    AvatarSize.sm => 12,
    AvatarSize.md => 15,
    AvatarSize.lg => 28,
    AvatarSize.xl => 38,
  };

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final bg = color ?? starling.colors.sage;
    const fg = Color(0xFFFDFBF5);

    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        color: imageProvider == null ? bg : null,
        shape: BoxShape.circle,
        image: imageProvider != null
            ? DecorationImage(image: imageProvider!, fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: imageProvider == null
          ? Text(
              initial,
              style: TextStyle(
                fontFamily: 'Fraunces',
                color: fg,
                fontSize: _fontSize,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            )
          : null,
    );
  }
}
