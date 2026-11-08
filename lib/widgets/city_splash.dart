import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The start screen (about 3 s while the app loads behind it): a fine isometric city,
/// like an architect's model, white blocks with hairline edges.
///
/// 1. the blocks rise a little from the ground
/// 2. our pins appear (red 0, yellow 1, green) and riders on bike, scooter, moped, moto
/// 3. your blue route lights up along the streets (you are the blue bubble)
/// 4. you arrive: the big green pin (4) pulses, the full ones fade
/// 5. the city fades into the app icon, "MOBIlity", the line under it and the four vehicles.
///
/// No text over the city; text only on the last screen.
class CitySplash extends StatefulWidget {
  final Duration show;
  const CitySplash({super.key, this.show = const Duration(milliseconds: 3200)});
  @override
  State<CitySplash> createState() => _CitySplashState();
}

class _CitySplashState extends State<CitySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2700))..forward();
  bool _fading = false;
  bool _gone = false;

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

  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

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
        child: ColoredBox(
          color: Colors.white,
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) {
              final t = _a.value;
              final cityOut = Curves.easeIn.transform(_seg(t, 0.74, 0.90));
              final endIn = Curves.easeOutCubic.transform(_seg(t, 0.80, 1.0));
              return Stack(fit: StackFit.expand, children: [
                if (cityOut < 1)
                  Opacity(
                    opacity: 1 - cityOut,
                    child: RepaintBoundary(child: CustomPaint(painter: _CityPainter(t))),
                  ),
                if (endIn > 0)
                  Opacity(
                    opacity: endIn,
                    child: Transform.scale(scale: 0.94 + 0.06 * endIn, child: const _EndCard()),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// The last screen: the icon, MOBIlity, the line under it, the four vehicles, Powered by.
class _EndCard extends StatelessWidget {
  const _EndCard();
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Stack(children: [
      Align(
        alignment: const Alignment(0, -0.12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x2213212B), blurRadius: 22, offset: Offset(0, 10))],
            ),
            child: Image.asset('assets/brand/app_icon.png', filterQuality: FilterQuality.medium),
          ),
          const SizedBox(height: 20),
          const Text('MOBIlity',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.6)),
          const SizedBox(height: 4),
          const Text('Your city. Your ride. A free spot.',
              style: TextStyle(fontSize: 13, color: Color(0xFF7E8D96))),
          const SizedBox(height: 18),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final v in _Veh.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CustomPaint(size: const Size(24, 24), painter: _VehPainter(v, const Color(0xFF8C9AA3), 1.6)),
              ),
          ]),
        ]),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 22 + bottom,
        child: const Text('Powered by MOBIlity',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0xFFB0BCC3))),
      ),
    ]);
  }
}

enum _Veh { bike, scooter, moped, moto }

/// Our small vehicle line icons (24 x 24 units).
Path _vehPath(_Veh v) {
  final p = Path();
  void c(double x, double y, double r) => p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
  switch (v) {
    case _Veh.bike:
      c(5.5, 16, 3.8);
      c(18.5, 16, 3.8);
      p
        ..moveTo(5.5, 16)
        ..lineTo(9.5, 9)
        ..lineTo(15.5, 9)
        ..lineTo(18.5, 16)
        ..moveTo(9.5, 9)
        ..lineTo(12, 16)
        ..lineTo(15.5, 9)
        ..moveTo(8, 6.5)
        ..lineTo(11, 6.5)
        ..moveTo(14.5, 6)
        ..lineTo(15.5, 9);
    case _Veh.scooter:
      c(5, 18, 2.6);
      c(19, 18, 2.6);
      p
        ..moveTo(5, 18)
        ..lineTo(15.5, 18)
        ..lineTo(18, 4.5)
        ..moveTo(16, 4.5)
        ..lineTo(20, 4.5);
    case _Veh.moped:
      c(6, 17.5, 3);
      c(18, 17.5, 3);
      p
        ..moveTo(3, 15)
        ..cubicTo(3, 11, 8, 10.5, 10.5, 12.5)
        ..lineTo(14.5, 12.5)
        ..lineTo(17, 6)
        ..moveTo(15.5, 6)
        ..lineTo(19.5, 6)
        ..moveTo(17, 6)
        ..lineTo(19.5, 14.5)
        ..moveTo(5, 10)
        ..lineTo(10.5, 10);
    case _Veh.moto:
      c(5, 16.5, 3.6);
      c(19, 16.5, 3.6);
      p
        ..moveTo(5, 16.5)
        ..lineTo(9, 10)
        ..lineTo(15.5, 10)
        ..lineTo(19, 16.5)
        ..moveTo(9, 10)
        ..lineTo(7, 8)
        ..lineTo(11.5, 8)
        ..moveTo(15.5, 10)
        ..lineTo(17, 6.5)
        ..lineTo(19.5, 6.5)
        ..moveTo(10.5, 13.5)
        ..lineTo(14, 13.5);
  }
  return p;
}

void _drawVeh(Canvas canvas, _Veh v, Offset center, double size, Color color, double stroke) {
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(size / 24);
  canvas.drawPath(
    _vehPath(v),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 24 / size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color,
  );
  canvas.restore();
}

class _VehPainter extends CustomPainter {
  final _Veh v;
  final Color color;
  final double stroke;
  _VehPainter(this.v, this.color, this.stroke);
  @override
  void paint(Canvas canvas, Size size) => _drawVeh(canvas, v, size.center(Offset.zero), size.width, color, stroke);
  @override
  bool shouldRepaint(covariant _VehPainter o) => false;
}

/// The fine isometric city, its pins, riders and your route, at time [t] (0..1).
class _CityPainter extends CustomPainter {
  final double t;
  _CityPainter(this.t);

  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  // the city: 3 small white blocks per square, a park and the lake (deterministic)
  static final List<_Block> _blocks = () {
    final out = <_Block>[];
    var seed = 7;
    double rnd() => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    for (var i = -6; i < 13; i++) {
      for (var j = -6; j < 13; j++) {
        final x0 = i * 3 + .8, y0 = j * 3 + .8;
        if (i == 2 && j == 0) {
          out.add(_Block(x0, y0, 1.5, 1.5, 0, kind: 1));
          continue;
        }
        if (i == 0 && j == 2) {
          out.add(_Block(x0, y0, 1.5, 1.5, 0, kind: 2));
          continue;
        }
        out.add(_Block(x0, y0, 1.4, .75, .3 + rnd() * .9));
        out.add(_Block(x0, y0 + .9, .6, .5, .2 + rnd() * .4));
        out.add(_Block(x0 + .8, y0 + .95, .6, .45, .15 + rnd() * .3));
      }
    }
    out.sort((a, b) => (a.x0 + a.w + a.y0 + a.d).compareTo(b.x0 + b.w + b.y0 + b.d));
    return out;
  }();

  static const _route = [Offset(0, 6), Offset(3, 6), Offset(3, 3), Offset(6, 3), Offset(6, 1.5)];
  // x, y, colour, number (only the big one shows it)
  static const _pins = <(double, double, Color, String, bool)>[
    (1.5, 3, AppColors.red, '0', false),
    (6, 4.6, AppColors.yellow, '1', false),
    (9, 7.5, AppColors.green, '2', false),
    (4.5, 9, AppColors.red, '0', false),
    (-1.5, 6, AppColors.green, '3', false),
    (6, 1.5, AppColors.green, '4', true),
  ];
  // the other riders: vehicle, from, to
  static const _riders = <(_Veh, Offset, Offset)>[
    (_Veh.scooter, Offset(3, 1), Offset(0, 1.5)),
    (_Veh.moped, Offset(9, 4.2), Offset(9, 1)),
    (_Veh.moto, Offset(7.2, 9), Offset(4, 9)),
    (_Veh.bike, Offset(-1.5, 3), Offset(-1.5, 7.5)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = w / 11.3;
    final cx = w / 2, cy = h * 0.46 - 4.2 * s;
    Offset P(double x, double y, [double z = 0]) => Offset(cx + (x - y) * .866 * s, cy + (x + y) * .5 * s - z * s);

    final rise = 0.25 + 0.75 * Curves.easeOutCubic.transform(_seg(t, 0.0, 0.22));
    final pinsIn = Curves.easeOutBack.transform(_seg(t, 0.14, 0.32));
    final routeF = Curves.easeInOut.transform(_seg(t, 0.30, 0.68));
    final arrive = _seg(t, 0.66, 0.80);
    final move = Curves.easeInOut.transform(_seg(t, 0.22, 0.74));

    // streets: soft grey bands
    final street = Paint()
      ..color = const Color(0xFFEEF2F4)
      ..strokeWidth = s * .9;
    for (var k = -9; k <= 24; k += 3) {
      canvas.drawLine(P(k.toDouble(), -12), P(k.toDouble(), 30), street);
      canvas.drawLine(P(-12, k.toDouble()), P(30, k.toDouble()), street);
    }

    // the planned route (grey dots) and the travelled part (blue)
    final pts = _route.map((p) => P(p.dx, p.dy)).toList();
    final full = Path()..addPolygon(pts, false);
    final dot = Paint()..color = const Color(0xFFB7C3CB);
    for (final m in full.computeMetrics()) {
      for (double d = 0; d < m.length; d += 6) {
        canvas.drawCircle(m.getTangentForOffset(d)!.position, 0.7, dot);
      }
    }
    Offset me = pts.first;
    if (routeF > 0) {
      final part = Path();
      for (final m in full.computeMetrics()) {
        part.addPath(m.extractPath(0, m.length * routeF), Offset.zero);
        me = m.getTangentForOffset(m.length * routeF)!.position;
      }
      canvas.drawPath(
          part,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = AppColors.blue.withValues(alpha: .18));
      canvas.drawPath(
          part,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = AppColors.blue);
    }

    // the green spot pulses when you arrive
    if (arrive > 0) {
      final g = P(6, 1.5);
      final pulse = math.sin(arrive * math.pi);
      canvas.drawOval(Rect.fromCenter(center: g, width: s * 3.2, height: s * 1.6),
          Paint()..color = AppColors.green.withValues(alpha: .12 * arrive));
      canvas.drawOval(
          Rect.fromCenter(center: g, width: s * (3.4 + 2.2 * arrive), height: s * (1.7 + 1.1 * arrive)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = AppColors.green.withValues(alpha: .35 * pulse));
    }

    // things standing on the map, back to front: blocks, pins, riders
    final items = <(double, void Function())>[];
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFC8D2D9);
    final park = Paint()..color = const Color(0xFFD7EACB);
    final parkEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = const Color(0xFFB9D8A4);
    for (final b in _blocks) {
      final mid = P(b.x0 + b.w / 2, b.y0 + b.d / 2);
      if (mid.dx < -3 * s || mid.dx > w + 3 * s || mid.dy < -3 * s || mid.dy > h + 3 * s) continue;
      if (b.kind == 1) {
        for (final o in const [Offset(.4, .4), Offset(1.1, .5), Offset(.7, 1.1), Offset(1.4, 1.3), Offset(.3, 1.4)]) {
          items.add((b.x0 + o.dx + b.y0 + o.dy, () {
            final q = P(b.x0 + o.dx, b.y0 + o.dy, .32);
            canvas.drawCircle(q, s * .26, park);
            canvas.drawCircle(q, s * .26, parkEdge);
          }));
        }
        continue;
      }
      if (b.kind == 2) {
        canvas.drawPath(
            Path()
              ..addPolygon([P(b.x0, b.y0), P(b.x0 + 1.5, b.y0), P(b.x0 + 1.5, b.y0 + 1.5), P(b.x0, b.y0 + 1.5)], true),
            Paint()..color = const Color(0xFFE6F0FC));
        continue;
      }
      final x0 = b.x0, y0 = b.y0, x1 = b.x0 + b.w, y1 = b.y0 + b.d, z = b.h * rise;
      items.add((x1 + y1, () {
        void face(List<Offset> ps, Color c) {
          final path = Path()..addPolygon(ps, true);
          canvas.drawPath(path, Paint()..color = c);
          canvas.drawPath(path, line);
        }

        face([P(x0, y1), P(x1, y1), P(x1, y1, z), P(x0, y1, z)], const Color(0xFFF7F9FA));
        face([P(x1, y0), P(x1, y1), P(x1, y1, z), P(x1, y0, z)], const Color(0xFFEDF1F4));
        face([P(x0, y0, z), P(x1, y0, z), P(x1, y1, z), P(x0, y1, z)], Colors.white);
      }));
    }

    if (pinsIn > 0) {
      for (final (x, y, c, n, big) in _pins) {
        final fade = (c != AppColors.green && arrive > 0) ? 1 - 0.65 * arrive : (c == AppColors.red && routeF > .3 ? .5 : 1.0);
        items.add((x + y + .3, () => _pin(canvas, P(x, y), big ? 7.5 : 5, c, big ? n : null, pinsIn, fade.toDouble())));
      }
      for (final (v, a, b) in _riders) {
        final p = Offset.lerp(a, b, move)!;
        items.add((p.dx + p.dy + .2, () => _rider(canvas, P(p.dx, p.dy), v, false, pinsIn)));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final i in items) {
      i.$2();
    }
    // you: the blue bubble on your route
    if (pinsIn > 0) _rider(canvas, me, _Veh.bike, true, pinsIn);

    // the edges melt into white
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(Offset(w / 2, h * .45), h * .62, [const Color(0x00FFFFFF), Colors.white],
              const [.55, 1]));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [
            Colors.white,
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Colors.white,
          ], const [
            0,
            .2,
            .78,
            .92
          ]));
  }

  // our pin, small: white inside, colour edge, a dot (or the number on the big one)
  void _pin(Canvas canvas, Offset at, double r, Color c, String? n, double k, double alpha) {
    if (k <= 0) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(k.clamp(0.0, 1.2));
    final col = c.withValues(alpha: alpha);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 1.1, height: r * .44),
        Paint()..color = c.withValues(alpha: .18 * alpha));
    final tip = -1.0, cy = tip - r * 2;
    final a = math.asin(r / (tip - cy).abs());
    final th = math.pi / 2 - a;
    final path = Path()
      ..moveTo(0, tip)
      ..lineTo(-r * math.sin(th), cy + r * math.cos(th))
      ..arcTo(Rect.fromCircle(center: Offset(0, cy), radius: r), math.pi / 2 + th, 2 * (math.pi - th), false)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: alpha));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = col);
    if (n == null) {
      canvas.drawCircle(Offset(0, cy), r * .38, Paint()..color = col);
    } else {
      final tp = TextPainter(
        text: TextSpan(text: n, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: col)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, cy - tp.height / 2));
    }
    canvas.restore();
  }

  // a rider: small white bubble with a fine vehicle icon (yours is blue)
  void _rider(Canvas canvas, Offset at, _Veh v, bool me, double k) {
    final r = (me ? 9.0 : 7.0) * k.clamp(0.0, 1.0);
    if (r <= 0) return;
    final c = me ? AppColors.blue : const Color(0xFF8C9AA3);
    final center = at - Offset(0, r + 2);
    if (me) canvas.drawCircle(center, r + 5, Paint()..color = AppColors.blue.withValues(alpha: .1));
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = me ? 1.3 : .8
          ..color = c);
    canvas.drawCircle(at, 1, Paint()..color = c);
    _drawVeh(canvas, v, center, r * 1.45, me ? AppColors.blue : AppColors.soft, me ? 1.3 : 1.0);
  }

  @override
  bool shouldRepaint(covariant _CityPainter o) => o.t != t;
}

class _Block {
  final double x0, y0, w, d, h;
  final int kind; // 0 building, 1 park, 2 lake
  const _Block(this.x0, this.y0, this.w, this.d, this.h, {this.kind = 0});
}
