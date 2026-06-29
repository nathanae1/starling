import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.planHint,
  });

  final String title;
  final String planHint;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: starling.typography.h1),
                const SizedBox(height: 12),
                Text(
                  planHint,
                  textAlign: TextAlign.center,
                  style: starling.typography.small.copyWith(
                    color: starling.colors.stone,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
