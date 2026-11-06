import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Round compass for the ride (in the style of the app: white disc, fine tick ring,
/// N in red, the needle in our blue).
///
/// Ride mode: the needle points where the rider is going, the centre shows the direction (NE, 45°).
/// Tap → wind mode: the needle shows where the wind blows (its tail is where it comes from),
/// the centre shows its speed. Tap again → back to the ride.
class RideCompass extends StatefulWidget {
  /// Where the rider is heading, degrees from north.
  final double heading;

  /// Wind: speed (km/h) and where it comes FROM (degrees). Null while the weather loads.
  final double? windKmh;
  final double? windFrom;
  final double size;
  const RideCompass({super.key, required this.heading, this.windKmh, this.windFrom, this.size = 76});

  @override
  State<RideCompass> createState() => _RideCompassState();
}

class _RideCompassState extends State<RideCompass> {
  bool _wind = false;

  static String _card(double d) {
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return names[((d % 360) / 45).round() % 8];
  }

  @override
  Widget build(BuildContext context) {
    final hasWind = widget.windKmh != null && widget.windFrom != null;
    final wind = _wind && hasWind;
    // the wind needle points where the wind goes (from + 180)
    final angle = wind ? (widget.windFrom! + 180) % 360 : widget.heading % 360;
    final accent = wind ? const Color(0xFF3FA9D6) : AppColors.blue;
    final s = widget.size;
    return GestureDetector(
      onTap: () => setState(() => _wind = !_wind),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: wind ? accent.withValues(alpha: 0.6) : AppColors.line, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: CustomPaint(
          painter: _CompassPainter(angle: angle, accent: accent, wind: wind),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (wind) ...[
                Icon(Icons.air, size: s * 0.15, color: accent),
                Text('${widget.windKmh!.round()}',
                    style: TextStyle(fontSize: s * 0.2, height: 1, fontWeight: FontWeight.w900, color: AppColors.ink)),
                Text('km/h', style: TextStyle(fontSize: s * 0.11, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.soft)),
              ] else ...[
                Text(_card(angle),
                    style: TextStyle(fontSize: s * 0.19, height: 1, fontWeight: FontWeight.w900, color: AppColors.ink)),
                Text('${angle.round()}°',
                    style: TextStyle(fontSize: s * 0.12, height: 1.15, fontWeight: FontWeight.w700, color: AppColors.soft)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double angle; // degrees from north, clockwise
  final Color accent;
  final bool wind;
  _CompassPainter({required this.angle, required this.accent, required this.wind});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // fine tick ring (every 6°, longer at N/E/S/W)
    final tick = Paint()
      ..color = AppColors.soft.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (int i = 0; i < 60; i++) {
      final a = i * 6 * math.pi / 180;
      final major = i % 15 == 0;
      final r1 = r - 5, r2 = r - (major ? 11 : 8);
      final d = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(c + d * r1, c + d * r2, tick..strokeWidth = major ? 1.6 : 0.9);
    }
    // N E S W (N in red), small, just inside the ticks
    void letter(String t, double deg, Color col) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontSize: r * 0.2, fontWeight: FontWeight.w900, color: col)),
        textDirection: TextDirection.ltr,
      )..layout();
      final a = deg * math.pi / 180;
      final p = c + Offset(math.sin(a), -math.cos(a)) * (r - 17);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    letter('N', 0, AppColors.red);
    letter('E', 90, AppColors.soft);
    letter('S', 180, AppColors.soft);
    letter('W', 270, AppColors.soft);

    // the needle: a tip on the ring where it points, a round tail on the other side
    final a = angle * math.pi / 180;
    final d = Offset(math.sin(a), -math.cos(a));
    final n = Offset(-d.dy, d.dx);
    final tip = c + d * (r - 3);
    final base = c + d * (r - 15);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + n.dx * 5.5, base.dy + n.dy * 5.5)
        ..lineTo(base.dx - n.dx * 5.5, base.dy - n.dy * 5.5)
        ..close(),
      Paint()..color = accent,
    );
    final tail = c - d * (r - 9);
    canvas.drawCircle(tail, wind ? 4 : 3, Paint()..color = accent.withValues(alpha: wind ? 1 : 0.45));
    if (wind) {
      // the wind comes from the tail: a thin line through the centre
      canvas.drawLine(tail, c - d * (r * 0.42), Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter o) => o.angle != angle || o.wind != wind || o.accent != accent;
}
