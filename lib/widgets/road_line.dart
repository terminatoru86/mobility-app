import 'package:flutter/material.dart';

import '../theme.dart';

/// A short piece of route line showing the road we are on now:
/// solid on bike lanes and protected lanes, broken (dashes) where nothing is marked.
/// Colours as in the trip summary.
class RoadLine extends StatelessWidget {
  final String kind; // 'Protected lanes', 'Bike lanes', 'Quiet streets', 'Shared roads', 'Main roads' or ''
  final double width;
  const RoadLine({super.key, required this.kind, this.width = 52});

  static const colors = {
    'Protected lanes': AppColors.green,
    'Quiet streets': Color(0xFF8CC063),
    'Bike lanes': AppColors.yellow,
    'Shared roads': Color(0xFFF08A3C),
    'Main roads': AppColors.red,
  };

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 10,
        child: CustomPaint(
          painter: _LinePainter(
            colors[kind] ?? AppColors.line,
            solid: kind == 'Protected lanes' || kind == 'Bike lanes',
          ),
        ),
      );
}

class _LinePainter extends CustomPainter {
  final Color c;
  final bool solid;
  _LinePainter(this.c, {required this.solid});

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final y = s.height / 2;
    if (solid) {
      canvas.drawLine(Offset(3, y), Offset(s.width - 3, y), p);
    } else {
      for (double x = 3; x < s.width - 3; x += 11) {
        canvas.drawLine(Offset(x, y), Offset((x + 5).clamp(0, s.width - 3), y), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.c != c || o.solid != solid;
}
