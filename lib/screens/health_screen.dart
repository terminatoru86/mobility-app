import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Demo rides until real recording arrives (M5).
class Ride {
  final String title;
  final double km;
  final Duration time;
  final Duration moving;
  final int climb, descent, maxAlt, watts, kcal;
  final bool pr;
  final List<double> profile; // altitude in m along the ride
  const Ride(this.title, this.km, this.time, this.moving, this.climb, this.descent, this.maxAlt, this.watts,
      this.kcal, this.profile,
      {this.pr = false});

  double get avg => km / (time.inSeconds / 3600);
  double get avgMoving => km / (moving.inSeconds / 3600);
}

List<double> _profile(int seed, int n, double base, double amp) {
  final r = math.Random(seed);
  var v = base;
  return [
    for (int i = 0; i < n; i++)
      v = (v + (r.nextDouble() - 0.5) * amp + math.sin(i / n * math.pi * 2) * amp * 0.15).clamp(0.0, base + amp * 6).toDouble(),
  ];
}

final _days = <int, List<Ride>>{
  // weekday index 0 = Monday
  0: [Ride('Commute', 12.1, const Duration(minutes: 41), const Duration(minutes: 36), 22, 20, 21, 68, 240, _profile(1, 60, 10, 3))],
  1: [],
  2: [Ride('Lakefront Trail', 18.6, const Duration(hours: 1, minutes: 12), const Duration(minutes: 63), 31, 29, 26, 71, 380, _profile(2, 80, 12, 4))],
  3: [
    Ride('Commute', 12.1, const Duration(minutes: 38), const Duration(minutes: 34), 20, 19, 22, 70, 230, _profile(3, 60, 10, 3)),
    Ride('Back home', 12.4, const Duration(minutes: 44), const Duration(minutes: 37), 24, 25, 22, 66, 245, _profile(4, 60, 10, 3)),
  ],
  4: [],
  5: [
    Ride('606 Trail + Lincoln Park', 33.4, const Duration(hours: 2, minutes: 38), const Duration(hours: 2, minutes: 4, seconds: 15),
        58, 52, 38, 74, 619, _profile(5, 120, 14, 5),
        pr: true),
  ],
  6: [Ride('Easy spin', 8.2, const Duration(minutes: 31), const Duration(minutes: 28), 12, 12, 19, 60, 150, _profile(6, 50, 10, 2))],
};

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _hm(Duration d) => '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String _range = 'Week';
  int _day = 5;

  @override
  Widget build(BuildContext context) {
    final all = _days.values.expand((e) => e).toList();
    final km = all.fold<double>(0, (a, r) => a + r.km);
    final time = all.fold<Duration>(Duration.zero, (a, r) => a + r.time);
    final climb = all.fold<int>(0, (a, r) => a + r.climb);
    final rides = _days[_day] ?? const <Ride>[];

    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const Text('Health', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('THIS WEEK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.soft)),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${km.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
              TextSpan(
                  text: '  · ${_hm(time)} h · $climb m climb',
                  style: const TextStyle(fontSize: 14, color: AppColors.soft, fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Day', label: Text('Day')),
            ButtonSegment(value: 'Week', label: Text('Week')),
            ButtonSegment(value: 'Month', label: Text('Month')),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tap a day to open it', style: TextStyle(fontSize: 12, color: AppColors.soft)),
            const SizedBox(height: 10),
            SizedBox(
              height: 130,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (int i = 0; i < 7; i++) Expanded(child: _bar(i)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(_dayNames[_day], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        if (rides.isEmpty)
          _card(child: const Text('No rides on this day', style: TextStyle(color: AppColors.soft)))
        else
          for (final r in rides)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DayScreen(day: _day, initial: rides.indexOf(r)))),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.directions_bike, color: AppColors.greenDark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${r.km.toStringAsFixed(1)} km · ${_hm(r.time)}',
                          style: const TextStyle(color: AppColors.soft, fontSize: 12.5)),
                    ]),
                  ),
                  if (r.pr) const _PrBadge(),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
      ]),
    );
  }

  Widget _bar(int i) {
    final km = (_days[i] ?? const <Ride>[]).fold<double>(0, (a, r) => a + r.km);
    final sel = i == _day;
    return GestureDetector(
      onTap: () => setState(() => _day = i),
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (km > 0)
          Text(km.toStringAsFixed(0),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sel ? AppColors.greenDark : AppColors.soft)),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 22,
          height: math.max(4, km / 35 * 90),
          decoration: BoxDecoration(
            color: sel ? AppColors.green : (km > 0 ? const Color(0xFFB9D7A2) : AppColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(_dayNames[i].substring(0, 3),
            style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w900 : FontWeight.w600)),
      ]),
    );
  }
}

Widget _card({required Widget child, VoidCallback? onTap}) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );

class _PrBadge extends StatelessWidget {
  const _PrBadge();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: AppColors.yellowTint, borderRadius: BorderRadius.circular(10)),
        child: const Text('PR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.yellowDark)),
      );
}

/// The screen of one day: values, elevation profile, record, more values.
class DayScreen extends StatefulWidget {
  final int day;
  final int initial;
  const DayScreen({super.key, required this.day, this.initial = 0});
  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  late int _day = widget.day;
  late int _ride = widget.initial;

  void _go(int d) {
    var k = _day;
    for (int i = 0; i < 7; i++) {
      k = (k + d) % 7;
      if (k < 0) k += 7;
      if ((_days[k] ?? const []).isNotEmpty) break;
    }
    setState(() {
      _day = k;
      _ride = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rides = _days[_day] ?? const <Ride>[];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(_dayNames[_day], style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: () => _go(1), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: rides.isEmpty
          ? const Center(child: Text('No rides on this day', style: TextStyle(color: AppColors.soft)))
          : _body(rides, rides[_ride.clamp(0, rides.length - 1)]),
    );
  }

  Widget _body(List<Ride> rides, Ride r) {
    Widget grid(List<(IconData, String, String, String)> items) => GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.05,
          children: [
            for (final it in items)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(it.$1, size: 18, color: AppColors.green),
                  const Spacer(),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: it.$2, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    TextSpan(text: ' ${it.$3}', style: const TextStyle(fontSize: 11, color: AppColors.soft)),
                  ])),
                  Text(it.$4, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
                ]),
              ),
          ],
        );

    return ListView(padding: const EdgeInsets.all(16), children: [
      grid([
        (Icons.timer_outlined, _hm(r.time), 'h:m', 'Duration'),
        (Icons.straighten, r.km.toStringAsFixed(1), 'km', 'Distance'),
        (Icons.speed, r.avg.toStringAsFixed(1), 'km/h', 'Avg speed'),
        (Icons.south_east, '${r.descent}', 'm', 'Descent'),
        (Icons.north_east, '${r.climb}', 'm', 'Climb'),
        (Icons.terrain, '${r.maxAlt}', 'm', 'Max altitude'),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 12, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: ElevationChart(profile: r.profile, km: r.km),
      ),
      if (rides.length > 1) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (int i = 0; i < rides.length; i++)
            ChoiceChip(
              label: Text('${rides[i].title} · ${rides[i].km.toStringAsFixed(1)} km'),
              selected: i == _ride,
              onSelected: (_) => setState(() => _ride = i),
            ),
        ]),
      ],
      if (r.pr) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.yellowTint, borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.yellow,
              child: Text('PR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Congratulations!', style: TextStyle(fontWeight: FontWeight.w900)),
                Text('This was your longest ride.', style: TextStyle(color: AppColors.yellowDark)),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      grid([
        (Icons.straighten, r.km.toStringAsFixed(1), 'km', 'Distance'),
        (Icons.north_east, '${r.climb}', 'm', 'Climb'),
        (Icons.timer, '${r.moving.inHours}:${(r.moving.inMinutes % 60).toString().padLeft(2, '0')}', '', 'Moving time'),
        (Icons.bolt, '${r.watts}', 'W', 'Avg power'),
        (Icons.speed, r.avgMoving.toStringAsFixed(1), 'km/h', 'Moving speed'),
        (Icons.local_fire_department_outlined, '${r.kcal}', 'kcal', 'Calories'),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.map_outlined), label: const Text('Route'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.download), label: const Text('GPX'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.share), label: const Text('Share'))),
      ]),
      const SizedBox(height: 8),
      const Text('Demo rides. Real recording and sensors come in milestone M5.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
    ]);
  }
}

/// Elevation profile: drag a finger on it to see the altitude of that point.
class ElevationChart extends StatefulWidget {
  final List<double> profile;
  final double km;
  const ElevationChart({super.key, required this.profile, required this.km});
  @override
  State<ElevationChart> createState() => _ElevationChartState();
}

class _ElevationChartState extends State<ElevationChart> {
  double? _x; // 0..1

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void put(Offset p) => setState(() => _x = (p.dx / c.maxWidth).clamp(0.0, 1.0).toDouble());
      return GestureDetector(
        onTapDown: (d) => put(d.localPosition),
        onHorizontalDragUpdate: (d) => put(d.localPosition),
        onHorizontalDragEnd: (_) {},
        child: SizedBox(
          height: 170,
          width: double.infinity,
          child: CustomPaint(painter: _ElevPainter(widget.profile, widget.km, _x)),
        ),
      );
    });
  }
}

class _ElevPainter extends CustomPainter {
  final List<double> v;
  final double km;
  final double? x;
  _ElevPainter(this.v, this.km, this.x);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 20.0;
    final w = size.width - left, h = size.height - bottom - 24;
    final maxV = v.reduce(math.max) + 2, minV = 0.0;
    Offset pt(int i) =>
        Offset(left + i / (v.length - 1) * w, 24 + h - (v[i] - minV) / (maxV - minV) * h);

    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String s, Offset o, {TextAlign align = TextAlign.left}) {
      tp.text = TextSpan(text: s, style: const TextStyle(fontSize: 10, color: AppColors.soft));
      tp.layout();
      final dx = align == TextAlign.center ? o.dx - tp.width / 2 : o.dx;
      tp.paint(canvas, Offset(dx, o.dy));
    }

    canvas.drawLine(Offset(left, 24), Offset(size.width, 24), grid);
    canvas.drawLine(Offset(left, 24 + h), Offset(size.width, 24 + h), grid);
    label('${maxV.round()} m', const Offset(0, 18));
    label('0 m', Offset(0, 24 + h - 6));
    for (int k = 0; k <= 4; k++) {
      label(k == 4 ? '${km.toStringAsFixed(1)} km' : (km * k / 4).toStringAsFixed(1),
          Offset(left + w * k / 4, size.height - 14),
          align: TextAlign.center);
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < v.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(left + w, 24 + h)
      ..lineTo(left, 24 + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.blue.withValues(alpha: 0.35), AppColors.blue.withValues(alpha: 0.03)],
        ).createShader(Rect.fromLTWH(left, 24, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    if (x != null) {
      final i = ((x! * size.width - left) / w * (v.length - 1)).round().clamp(0, v.length - 1);
      final p = pt(i);
      canvas.drawLine(Offset(p.dx, 24), Offset(p.dx, 24 + h), Paint()..color = AppColors.blue);
      canvas.drawCircle(p, 5, Paint()..color = AppColors.blue);
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
      final txt = '${v[i].round()} m';
      tp.text = TextSpan(text: txt, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800));
      tp.layout();
      final bx = (p.dx - tp.width / 2 - 7).clamp(0.0, math.max(0.0, size.width - tp.width - 14)).toDouble();
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(bx, 0, tp.width + 14, 20), const Radius.circular(10));
      canvas.drawRRect(r, Paint()..color = AppColors.blue);
      tp.paint(canvas, Offset(bx + 7, 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ElevPainter o) => o.x != x || o.v != v;
}
