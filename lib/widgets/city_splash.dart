import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// The start screen (about 3 s while the app loads behind it), in the app's own look:
/// a light map with fine streets, our pins (green / yellow / red) dropping onto it one after
/// the other, the "m" logo and MOBIlity in the middle, "Powered by MOBIlity" bottom-left.
/// (The city drone video idea is parked for now.)
class CitySplash extends StatefulWidget {
  final Duration show;
  const CitySplash({super.key, this.show = const Duration(milliseconds: 2900)});
  @override
  State<CitySplash> createState() => _CitySplashState();
}

class _CitySplashState extends State<CitySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  bool _fading = false;
  bool _gone = false;

  // where the pins land (fractions of the screen) and their status colour
  static const _pins = <(double, double, Color)>[
    (0.22, 0.24, AppColors.green),
    (0.74, 0.20, AppColors.yellow),
    (0.16, 0.70, AppColors.red),
    (0.84, 0.76, AppColors.green),
    (0.58, 0.82, AppColors.yellow),
    (0.36, 0.86, AppColors.green),
  ];

  @override
  void initState() {
    super.initState();
    Timer(widget.show, () {
      if (mounted) setState(() => _fading = true);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: _fading,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: const Duration(milliseconds: 450),
        onEnd: () {
          if (_fading && mounted) setState(() => _gone = true);
        },
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          return AnimatedBuilder(
            animation: _a,
            builder: (_, __) {
              final t = _a.value;
              final logoIn = Curves.easeOutBack.transform(((t - 0.05) / 0.45).clamp(0.0, 1.0));
              return Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Color(0xFFF1F4F5)),
                CustomPaint(painter: _Streets()),
                // pins dropping one after the other
                for (var i = 0; i < _pins.length; i++)
                  Builder(builder: (_) {
                    final start = 0.15 + i * 0.1;
                    final p = ((t - start) / 0.35).clamp(0.0, 1.0);
                    if (p <= 0) return const SizedBox.shrink();
                    final drop = Curves.bounceOut.transform(p);
                    final (x, y, c) = _pins[i];
                    return Positioned(
                      left: x * w - 14,
                      top: y * h - 40 - (1 - drop) * 60,
                      child: Opacity(opacity: math.min(1, p * 3), child: _MiniPin(c)),
                    );
                  }),
                // the logo, MOBIlity and the line under it
                Center(
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * logoIn,
                    child: Opacity(
                      opacity: logoIn.clamp(0.0, 1.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 96,
                          height: 96,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [BoxShadow(color: Color(0x2A13212B), blurRadius: 24, offset: Offset(0, 10))],
                          ),
                          child: SvgPicture.asset('assets/brand/logo_m.svg'),
                        ),
                        const SizedBox(height: 16),
                        const Text('MOBIlity',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        const Text('RACKS · PARKING · CHARGING · ROUTES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.soft, letterSpacing: 1.6)),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  bottom: 22 + MediaQuery.of(context).padding.bottom,
                  child: Row(children: [
                    SizedBox(width: 22, height: 22, child: SvgPicture.asset('assets/brand/logo_m.svg')),
                    const SizedBox(width: 8),
                    const Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Powered by ', style: TextStyle(fontWeight: FontWeight.w500)),
                        TextSpan(text: 'MOBIlity', style: TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                      style: TextStyle(color: AppColors.soft, fontSize: 13),
                    ),
                  ]),
                ),
              ]);
            },
          );
        }),
      ),
    );
  }
}

/// Fine white streets on the light background, like our calm map.
class _Streets extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final wide = Paint()
      ..color = Colors.white
      ..strokeWidth = 9;
    final thin = Paint()
      ..color = Colors.white
      ..strokeWidth = 4;
    final park = Paint()..color = const Color(0xFFE3EEDA);
    canvas.drawRRect(RRect.fromLTRBR(s.width * 0.55, s.height * 0.32, s.width * 0.95, s.height * 0.46, const Radius.circular(18)), park);
    for (double y = -40; y < s.height + 80; y += 70) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y + 34), y % 210 == 30 ? wide : thin);
    }
    for (double x = -60; x < s.width + 60; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x + 40, s.height), x % 192 == 4 ? wide : thin);
    }
    // a blue bike route across
    final route = Paint()
      ..color = AppColors.blue.withValues(alpha: 0.55)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(s.width * 0.05, s.height * 0.95)
        ..cubicTo(s.width * 0.3, s.height * 0.7, s.width * 0.1, s.height * 0.45, s.width * 0.5, s.height * 0.38)
        ..cubicTo(s.width * 0.85, s.height * 0.3, s.width * 0.7, s.height * 0.12, s.width * 0.95, s.height * 0.04),
      route,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Our pin, small: tinted inside, edge in the status colour, a ball under the tip.
class _MiniPin extends StatelessWidget {
  final Color c;
  const _MiniPin(this.c);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 40,
        child: CustomPaint(painter: _MiniPinPainter(c)),
      );
}

class _MiniPinPainter extends CustomPainter {
  final Color c;
  _MiniPinPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    const r = 11.0, cx = 14.0, cy = 12.0, tip = 33.0;
    final a = math.asin(r / (tip - cy));
    final t = math.pi / 2 - a;
    final path = Path()
      ..moveTo(cx, tip)
      ..lineTo(cx - r * math.sin(t), cy + r * math.cos(t))
      ..arcTo(Rect.fromCircle(center: const Offset(cx, cy), radius: r), math.pi / 2 + t, 2 * (math.pi - t), false)
      ..close();
    canvas.drawShadow(path, c, 2, false);
    canvas.drawPath(path, Paint()..color = Color.lerp(c, Colors.white, 0.8)!);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = c);
    canvas.drawCircle(const Offset(cx, 37.5), 2.6, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _MiniPinPainter o) => o.c != c;
}
