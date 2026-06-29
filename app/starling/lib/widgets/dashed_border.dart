import 'package:flutter/material.dart';

/// Dashed rounded-rectangle border used by the compose photo placeholder.
/// Wraps its [child] and paints the dashed stroke on top (inset by the stroke
/// width so the dashes don't clip against the parent).
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    this.radius = 14,
    this.color = const Color(0xFFE1D8C3),
    this.strokeWidth = 1.5,
    this.dashOn = 8,
    this.dashOff = 6,
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;
  final double dashOn;
  final double dashOff;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRoundedRectPainter(
        radius: radius,
        color: color,
        strokeWidth: strokeWidth,
        dashOn: dashOn,
        dashOff: dashOff,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  _DashedRoundedRectPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
    required this.dashOn,
    required this.dashOff,
  });

  final double radius;
  final Color color;
  final double strokeWidth;
  final double dashOn;
  final double dashOff;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius - inset),
    );

    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashOn).clamp(0, metric.length).toDouble();
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + dashOff;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashOn != dashOn ||
      old.dashOff != dashOff;
}
