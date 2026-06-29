import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';

enum StarlingTab { feed, friends, rooms, you }

class StarlingBottomTabBar extends StatelessWidget {
  const StarlingBottomTabBar({
    super.key,
    required this.current,
    required this.onTap,
    this.badges = const {},
  });

  final StarlingTab current;
  final ValueChanged<StarlingTab> onTap;

  /// Per-tab badge counts. A count > 0 renders a small dot on that tab's
  /// icon; the numeric value is not shown (calm-by-design — see CLAUDE.md
  /// "No push notifications").
  final Map<StarlingTab, int> badges;

  static const _tabs = <_TabDef>[
    _TabDef(StarlingTab.feed, 'Feed'),
    _TabDef(StarlingTab.friends, 'Friends'),
    _TabDef(StarlingTab.rooms, 'Rooms'),
    _TabDef(StarlingTab.you, 'You'),
  ];

  IconData _iconFor(StarlingTab tab) {
    switch (tab) {
      case StarlingTab.feed:
        return LucideIcons.house;
      case StarlingTab.friends:
        return LucideIcons.users;
      case StarlingTab.rooms:
        return LucideIcons.radio;
      case StarlingTab.you:
        return LucideIcons.user;
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: starling.colors.paper,
        border: Border(top: BorderSide(color: starling.colors.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        10,
        8,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: _TabButton(
                label: tab.label,
                icon: _iconFor(tab.id),
                active: tab.id == current,
                hasBadge: (badges[tab.id] ?? 0) > 0,
                onTap: () => onTap(tab.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabDef {
  const _TabDef(this.id, this.label);
  final StarlingTab id;
  final String label;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.hasBadge = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool hasBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final color = active ? starling.colors.sage : starling.colors.stone;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                if (hasBadge)
                  Positioned(
                    top: -1,
                    right: -3,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: starling.colors.clay,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: starling.colors.paper,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'IBMPlexSans',
                fontSize: 10.5,
                letterSpacing: 0.1,
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
