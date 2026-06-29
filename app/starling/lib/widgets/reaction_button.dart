import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';
import 'buttons.dart';

/// Heart toggle for the post detail action row and the post card. Filled
/// clay when [liked], outline graphite otherwise. Tapping fires the
/// `heart-pop` scale animation regardless of like state — the animation
/// is the tactile receipt that the tap registered.
class ReactionButton extends StatefulWidget {
  const ReactionButton({
    super.key,
    required this.liked,
    required this.count,
    required this.onTap,
    this.iconSize = 22,
    this.showCount = true,
    this.compact = false,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;
  final double iconSize;
  final bool showCount;

  /// Compact mode lays out without the [StarlingIconButton] tap padding —
  /// used by the post card so the heart sits inline with the chat icon
  /// and count.
  final bool compact;

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl.duration = StarlingTheme.of(context).motion.heartPop;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final color = widget.liked
        ? starling.colors.clay
        : starling.colors.graphite;
    final iconData = widget.liked ? LucideIcons.heart : LucideIcons.heart;

    final scaled = ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.25,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut)),
      child: Icon(iconData, size: widget.iconSize, color: color),
    );

    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        scaled,
        if (widget.showCount && widget.count > 0) ...[
          const SizedBox(width: 6),
          Text('${widget.count}', style: starling.typography.small),
        ],
      ],
    );

    if (widget.compact) {
      return Semantics(
        button: true,
        label: widget.liked ? 'Unlike' : 'Like',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: body,
          ),
        ),
      );
    }
    return StarlingIconButton(
      onPressed: _handleTap,
      semanticLabel: widget.liked ? 'Unlike' : 'Like',
      child: body,
    );
  }
}
