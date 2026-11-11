import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/routing.dart';
import '../theme.dart';
import 'share_pin.dart';

/// Walking: about 80 metres a minute, paths are longer than the straight line.
int walkMinutes(double meters) => (meters / 80).ceil().clamp(1, 999);

double metersTo(Place p) => const Distance()(userPos, p.pos) * 1.25;

/// Where the operator's own app (or page) opens: the ride is unlocked and paid there.
String operatorUrl(Place p) {
  final name = (p.operatorName ?? '').toLowerCase();
  return name.contains('divvy')
      ? 'https://divvybikes.com/how-it-works/get-the-app'
      : name.contains('lime')
          ? 'https://www.li.me/'
          : name.contains('bird')
              ? 'https://www.bird.co/'
              : name.contains('spin')
                  ? 'https://www.spin.app/'
                  : 'https://www.google.com/search?q=${Uri.encodeComponent(p.operatorName ?? 'bike share')}';
}

/// The boxes inside the tinted place sheet: white, a little see-through.
const kFrost = Color(0xB8FFFFFF);

/// green from 3 up, yellow 1–2, red 0: the same rule on the pin and in the sheet
Status countStatus(int n) => n == 0 ? Status.full : (n <= 2 ? Status.almost : Status.free);

/// A station in the place sheet: the four numbers (e-bikes, classic, scooters, open docks),
/// each in its own colour, then one slim line with the walk there.
class ShareCounts extends StatelessWidget {
  final Place place;
  const ShareCounts(this.place, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = place.share!;
    Widget tile(IconData icon, int n, String label, {bool dock = false}) {
      final c = colorsFor(dock ? Status.neutral : countStatus(n));
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 7),
          // frosted white on the tinted sheet; the colour stays on the number
          decoration: BoxDecoration(color: kFrost, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: c.dark),
              const SizedBox(width: 4),
              Text('$n', style: TextStyle(fontSize: 18, height: 1.1, fontWeight: FontWeight.w900, color: c.dark)),
            ]),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
          ]),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        tile(Icons.electric_bike_rounded, s.ebikes, 'E-bikes'),
        tile(Icons.pedal_bike_rounded, s.classic, 'Classic'),
        tile(Icons.electric_scooter_rounded, s.scooters, 'Scooters'),
        tile(Icons.local_parking_rounded, s.docks ?? 0, 'Open docks', dock: true),
      ]),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: WalkLine(metersTo(place))),
    ]);
  }
}

/// One slim line: the walker in a dark circle, the minutes, a dashed line, the distance.
class WalkLine extends StatelessWidget {
  final double meters;
  const WalkLine(this.meters, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 4, right: 14),
        decoration: BoxDecoration(color: kFrost, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const WalkerDot(),
          const SizedBox(width: 8),
          Text('${walkMinutes(meters)} min',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(width: 5),
          const Text('walk', style: TextStyle(fontSize: 12, color: AppColors.soft)),
          const SizedBox(width: 8),
          const Expanded(child: CustomPaint(size: Size(double.infinity, 2), painter: _Dashes())),
          const SizedBox(width: 8),
          Text(fmtDistance(meters), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
        ]),
      );
}

/// The walker, white on a dark circle (also in the minutes bubble on the map).
class WalkerDot extends StatelessWidget {
  final double size;
  const WalkerDot({super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Icon(Icons.directions_walk_rounded, size: size * .64, color: Colors.white),
      );
}

class _Dashes extends CustomPainter {
  const _Dashes();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.grey
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 4, size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => false;
}

/// One vehicle on the street, in the place sheet: its picture with the battery and how far
/// it still goes (in place of minutes and arrival time), then the walking time (in place of distance).
class ShareVehicleRow extends StatelessWidget {
  final Place place;
  const ShareVehicleRow(this.place, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = place.share!;
    final m = metersTo(place);
    final miles = s.rangeM == null ? null : s.rangeM! / 1609.34;
    final range = miles == null ? null : '${miles < 10 ? miles.toStringAsFixed(1) : miles.round()} mi left';
    final c = chargeColor(s.battery);
    Widget box(Widget child, {int flex = 1}) => Expanded(
          flex: flex,
          child: Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: kFrost, borderRadius: BorderRadius.circular(14)),
            child: child,
          ),
        );
    return Row(children: [
      box(
        flex: 3,
        Row(children: [
          SizedBox(width: 76, height: 60, child: Image.asset(s.vehicle.asset, fit: BoxFit.contain)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (s.battery != null)
                Row(children: [
                  Icon(Icons.bolt_rounded, size: 20, color: c),
                  Text('${s.battery}%', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ])
              else if (range != null)
                Row(children: [
                  Icon(Icons.bolt_rounded, size: 20, color: c),
                  Text(range.replaceAll(' left', ''), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ])
              else
                Text(s.vehicle.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                  s.battery != null
                      ? (range ?? 'battery')
                      : (range != null ? 'left' : 'battery not shared'),
                  style: const TextStyle(fontSize: 11, color: AppColors.soft)),
            ]),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      box(
        flex: 2,
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${walkMinutes(m)} min', maxLines: 1, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          Text('walk · ${fmtDistance(m)}', maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
        ]),
      ),
    ]);
  }
}

/// The minutes on the walking line: a white bubble with the walker.
class WalkBubble extends StatelessWidget {
  final int minutes;
  const WalkBubble(this.minutes, {super.key});
  static const double width = 92, height = 32;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 11, 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const WalkerDot(size: 24),
            const SizedBox(width: 6),
            Text('$minutes min',
                style: const TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ]),
        ),
      );
}
