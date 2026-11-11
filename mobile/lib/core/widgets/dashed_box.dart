import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Container with a dashed rounded border (CSS `border: 1.5px dashed`).
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.color = AppColors.subtle,
    this.strokeWidth = 1.5,
    this.radius = 12,
    this.background,
    this.padding = EdgeInsets.zero,
    this.dash = 5,
    this.gap = 4,
  });

  final Widget child;
  final Color color;
  final double strokeWidth;
  final double radius;
  final Color? background;
  final EdgeInsets padding;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(color, strokeWidth, radius, dash, gap),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius)),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.width, this.radius, this.dash, this.gap);

  final Color color;
  final double width;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = width / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - width, size.height - width),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.width != width || old.radius != radius;
}
