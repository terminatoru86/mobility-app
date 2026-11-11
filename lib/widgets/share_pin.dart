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
///  · a station (hub): one white pill, each kind with its drawing and its number
///    (e-bikes with a bolt, classic bikes, scooters); grey with 0 when it is empty
///  · a vehicle left on the street: a small white drop with the bike or the scooter
///    and a bolt in the colour of its battery
class SharePin extends StatelessWidget {
  final Place place;
  final bool selected;

  /// further out: the hub shows one drawing and the total only
  final bool compact;
  const SharePin({super.key, required this.place, this.selected = false, this.compact = false});

  static const double height = 46;

  /// (drawing, number) for every kind the hub holds now
  static List<(Vehicle, int)> kinds(ShareInfo s) => [
        if (s.ebikes > 0) (Vehicle.ebike, s.ebikes),
        if (s.classic > 0) (Vehicle.bike, s.classic),
        if (s.scooters > 0) (Vehicle.scooter, s.scooters),
      ];

  static double widthFor(Place p, {bool compact = false}) {
    final s = p.share!;
    if (s.street) return 40;
    final n = compact ? 1 : kinds(s).length;
    return n <= 1 ? 58 : 18.0 + n * 40;
  }

  @override
  Widget build(BuildContext context) {
    final s = place.share!;
    final w = widthFor(place, compact: compact);
    return SizedBox(
      width: w,
      height: height,
      child: Transform.scale(
        scale: selected ? 1.15 : 1,
        alignment: Alignment.bottomCenter,
        child: s.street ? _street(s) : _hub(s),
      ),
    );
  }

  Widget _hub(ShareInfo s) {
    final empty = s.total == 0 || place.status == Status.full;
    final edge = empty ? AppColors.grey : AppColors.primary;
    final all = kinds(s);
    final shown = empty
        ? const <(Vehicle, int)>[]
        : compact
            ? [(all.first.$1, s.total)]
            : all;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: empty ? AppColors.greyTint : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: edge, width: selected ? 2 : 1.4),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (empty) ...[
            const Icon(Icons.pedal_bike_rounded, size: 16, color: AppColors.grey),
            const SizedBox(width: 3),
            const Text('0', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.greyDark)),
          ] else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppColors.line),
              Icon(shareIcon(shown[i].$1),
                  size: 16, color: shown[i].$1 == Vehicle.bike ? AppColors.primary : AppColors.greenDark),
              const SizedBox(width: 2),
              Text('${shown[i].$2}',
                  style: const TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w900, color: AppColors.ink)),
            ],
        ]),
      ),
      // the stem down to the map point
      Container(width: 2, height: 9, color: edge),
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: edge, border: Border.all(color: Colors.white, width: 1.5)),
      ),
    ]);
  }

  Widget _street(ShareInfo s) {
    final c = chargeColor(s.battery);
    return Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
      Positioned(bottom: 0, child: CustomPaint(size: const Size(34, 44), painter: _Drop(selected))),
      Positioned(top: 9, child: Icon(shareIcon(s.vehicle), size: 19, color: AppColors.primary)),
      // the bolt: the colour says how much battery is left
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c, border: Border.all(color: Colors.white, width: 1.5)),
          child: const Icon(Icons.bolt_rounded, size: 10, color: Colors.white),
        ),
      ),
    ]);
  }
}

/// White drop with a dark edge: round head, point down on the map.
class _Drop extends CustomPainter {
  final bool selected;
  const _Drop(this.selected);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const r = 15.0, cy = 18.0;
    final path = Path()
      ..moveTo(cx, size.height)
      ..quadraticBezierTo(cx - 4, cy + r, cx - r * .86, cy + r * .5)
      ..arcToPoint(Offset(cx + r * .86, cy + r * .5), radius: const Radius.circular(r), largeArc: true)
      ..quadraticBezierTo(cx + 4, cy + r, cx, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0x66000000), 3, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.4
          ..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_Drop old) => old.selected != selected;
}
