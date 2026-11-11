import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';

/// Battery colour: green charged, yellow half, red low.
Color chargeColor(int? pct) =>
    pct == null ? AppColors.green : (pct >= 50 ? AppColors.green : (pct >= 20 ? AppColors.yellow : AppColors.red));

IconData shareIcon(Vehicle v) => switch (v) {
      Vehicle.scooter => Icons.electric_scooter_rounded,
      Vehicle.ebike => Icons.electric_bike_rounded,
      _ => Icons.pedal_bike_rounded,
    };

/// Ride-share pins, shown when only Sharing is picked.
///  · a station (hub), from far: a full pill in the colour of what it holds (green from 3 up,
///    yellow 1–2), the vehicle in a dark circle with the other kinds tucked behind it, then the
///    total. Empty: a small red drop with 0.
///  · the same station [open] (tapped, or zoomed right in): every kind in its own circle with
///    its number. The tapped one turns dark.
///  · a vehicle left on the street: a white drop with its drawing and a bolt in the colour of
///    its battery. Tapped, it turns dark.
class SharePin extends StatelessWidget {
  final Place place;
  final bool selected;
  final bool open;
  const SharePin({super.key, required this.place, this.selected = false, this.open = false});

  static const double height = 40;
  static const double _d = 22; // the circle with the drawing

  /// (drawing, number) for every kind the hub holds now
  static List<(Vehicle, int)> kinds(ShareInfo s) => [
        if (s.ebikes > 0) (Vehicle.ebike, s.ebikes),
        if (s.classic > 0) (Vehicle.bike, s.classic),
        if (s.scooters > 0) (Vehicle.scooter, s.scooters),
      ];

  static bool _empty(Place p) => p.share!.total == 0 || p.status == Status.full;

  static double _digits(int n) => 8.5 * '$n'.length;

  static double widthFor(Place p, {bool open = false}) {
    final s = p.share!;
    if (s.street) return 32;
    if (_empty(p)) return 30;
    final k = kinds(s);
    if (!open) return 2 + _d + (k.length - 1) * 6 + 6 + _digits(s.total) + 9 + 6;
    var w = 2.0 + 9 + 6;
    for (final (_, n) in k) {
      w += _d + 5 + _digits(n);
    }
    return w + (k.length - 1) * 8;
  }

  @override
  Widget build(BuildContext context) {
    final s = place.share!;
    return SizedBox(
      width: widthFor(place, open: open),
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: s.street ? _street(s) : (_empty(place) ? _zero() : _hub(s)),
      ),
    );
  }

  static const _shadow = [BoxShadow(color: Color(0x4D000000), blurRadius: 4, offset: Offset(0, 2))];
  static const _dark = StatusColors(AppColors.primary, AppColors.primary, Color(0xFF0F1E24));

  Widget _circle(Vehicle? v, Color c) => Container(
        width: _d,
        height: _d,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: c, border: Border.all(color: const Color(0x30FFFFFF), width: 1)),
        child: v == null ? null : Icon(shareIcon(v), size: 14, color: Colors.white),
      );

  Widget _num(int n, Color c) => Text('$n',
      style: TextStyle(fontSize: 14, height: 1, fontWeight: FontWeight.w900, color: c));

  Widget _pill(StatusColors c, List<Widget> children) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 26,
          padding: const EdgeInsets.only(left: 2, right: 9),
          decoration: BoxDecoration(color: c.main, borderRadius: BorderRadius.circular(13), boxShadow: _shadow),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
        CustomPaint(size: const Size(11, 7), painter: _Tail(c.main)),
      ]);

  Widget _hub(ShareInfo s) {
    final st = place.status == Status.almost || s.total <= 2 ? Status.almost : Status.free;
    final c = selected ? _dark : colorsFor(st);
    // white numbers; on yellow they are dark, to stay readable
    final ink = !selected && st == Status.almost ? const Color(0xFF2E2200) : Colors.white;
    final k = kinds(s);
    if (open) {
      return _pill(c, [
        for (var i = 0; i < k.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _circle(k[i].$1, c.dark),
          const SizedBox(width: 5),
          _num(k[i].$2, ink),
        ],
      ]);
    }
    // from far: the first kind in front, the others peeking out behind it on the right
    final extra = (k.length - 1) * 6.0;
    return _pill(c, [
      SizedBox(
        width: _d + extra,
        height: _d,
        child: Stack(children: [
          for (var i = k.length - 1; i > 0; i--) Positioned(left: i * 6.0, child: _circle(null, c.dark)),
          Positioned(left: 0, child: _circle(k.first.$1, c.dark)),
        ]),
      ),
      const SizedBox(width: 6),
      _num(s.total, ink),
    ]);
  }

  Widget _zero() {
    final c = selected ? AppColors.primary : AppColors.red;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: _shadow),
        child: _num(0, Colors.white),
      ),
      CustomPaint(size: const Size(11, 7), painter: _Tail(c)),
    ]);
  }

  Widget _street(ShareInfo s) => SizedBox(
        width: 30,
        height: 38,
        child: Stack(alignment: Alignment.topCenter, children: [
          Positioned.fill(child: CustomPaint(painter: _Drop(selected ? AppColors.primary : Colors.white))),
          Positioned(top: 3.5, child: Icon(shareIcon(s.vehicle), size: 15, color: selected ? Colors.white : AppColors.ink)),
          // the bolt under the drawing: its colour says how much battery is left
          Positioned(top: 16, child: Icon(Icons.bolt_rounded, size: 12, color: chargeColor(s.battery))),
        ]),
      );
}

/// The small point under a pill, down to the map point.
class _Tail extends CustomPainter {
  final Color color;
  const _Tail(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(0, -1)
          ..lineTo(size.width, -1)
          ..lineTo(size.width / 2, size.height)
          ..close(),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Tail old) => old.color != color;
}

/// A drop: round head, point down on the map.
class _Drop extends CustomPainter {
  final Color color;
  const _Drop(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const r = 14.0;
    final path = Path()
      ..moveTo(cx, size.height)
      ..lineTo(cx - 5, r * 1.9)
      ..arcToPoint(Offset(cx + 5, r * 1.9), radius: const Radius.circular(r), largeArc: true)
      ..close();
    canvas.drawShadow(path, const Color(0x80000000), 2.5, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Drop old) => old.color != color;
}
