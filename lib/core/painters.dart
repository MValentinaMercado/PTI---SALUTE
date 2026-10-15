import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Círculo con trazo punteado. Usado en el card de salud del Home.
class DashedCirclePainter extends CustomPainter {
  final Color color;
  final int dashCount;
  final double gapFraction;
  final double strokeWidth;

  const DashedCirclePainter({
    required this.color,
    this.dashCount    = 20,
    this.gapFraction  = 0.4,
    this.strokeWidth  = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color      = color
      ..style      = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;
    final dashAngle = 2 * math.pi / dashCount;

    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * dashAngle,
        dashAngle * (1 - gapFraction),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DashedCirclePainter old) =>
      old.color != color ||
          old.dashCount != dashCount ||
          old.gapFraction != gapFraction ||
          old.strokeWidth != strokeWidth;
}