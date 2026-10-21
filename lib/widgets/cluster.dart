import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../theme.dart';

/// A group of nearby places when the map is zoomed out.
class Cluster {
  final LatLng center;
  final List<Place> places;
  Cluster(this.center, this.places);
}

/// Groups places on a grid whose cell size depends on the zoom.
List<Cluster> clusterPlaces(List<Place> places, double zoom) {
  final cell = 0.02 * math.pow(2, 12 - zoom); // degrees
  final Map<String, List<Place>> cells = {};
  for (final p in places) {
    final key = '${(p.pos.latitude / cell).floor()}:${(p.pos.longitude / cell).floor()}';
    cells.putIfAbsent(key, () => []).add(p);
  }
  return cells.values.map((ps) {
    final lat = ps.map((p) => p.pos.latitude).reduce((a, b) => a + b) / ps.length;
    final lng = ps.map((p) => p.pos.longitude).reduce((a, b) => a + b) / ps.length;
    return Cluster(LatLng(lat, lng), ps);
  }).toList();
}

/// Compass-style cluster: dotted inner circle with the count,
/// coloured arcs placed in the direction where the places are (north up).
class ClusterBadge extends StatelessWidget {
  final Cluster cluster;
  final double size;
  const ClusterBadge({super.key, required this.cluster, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.9),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: CustomPaint(
        painter: _CompassPainter(cluster),
        child: Center(
          child: Text('${cluster.places.length}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.ink)),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Cluster c;
  _CompassPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    // dotted inner circle
    final dot = Paint()..color = const Color(0xFF4E5F69);
    for (int i = 0; i < 36; i++) {
      final a = i * math.pi / 18;
      canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * (r * 0.62), 0.7, dot);
    }
    // one arc per place, in its direction from the cluster center
    final step = math.max(1, (c.places.length / 24).ceil()); // at most ~24 arcs
    for (int k = 0; k < c.places.length; k += step) {
      final p = c.places[k];
      final dx = p.pos.longitude - c.center.longitude;
      final dy = p.pos.latitude - c.center.latitude;
      final bearing = (dx == 0 && dy == 0) ? -math.pi / 2 : math.atan2(-dy, dx); // screen angle, north up
      final col = colorsFor(p.shownStatus == Status.neutral ? Status.unknown : p.shownStatus).main;
      final arc = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r * 0.82), bearing - 0.28, 0.56, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.c != c;
}

/// Modern group: white disc, a thin ring split by status (free / almost / full / no data), the count inside.
class DonutCluster extends StatelessWidget {
  final List<Place> places;
  final double size;
  const DonutCluster({super.key, required this.places, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final n = places.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: AppColors.ink.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: CustomPaint(
        painter: _DonutPainter(places),
        child: Center(
          child: Text(
            n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: size < 40 ? 11.5 : 13.5,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Place> places;
  _DonutPainter(this.places);

  @override
  void paint(Canvas canvas, Size size) {
    final counts = <Status, int>{};
    for (final p in places) {
      final s = p.shownStatus == Status.neutral ? Status.unknown : p.shownStatus;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final total = places.length.toDouble();
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 4);
    const gap = 0.07; // small gap between colours
    var start = -math.pi / 2;
    final order = [Status.free, Status.almost, Status.full, Status.unknown];
    final present = order.where((s) => (counts[s] ?? 0) > 0).length;
    for (final s in order) {
      final c = counts[s] ?? 0;
      if (c == 0) continue;
      final sweep = 2 * math.pi * c / total;
      final paint = Paint()
        ..color = colorsFor(s).main
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round;
      final g = present > 1 ? gap : 0.0;
      canvas.drawArc(rect, start + g / 2, math.max(0.02, sweep - g), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.places != places;
}

/// Small frosted label on the ring ("22 mi around you").
class RingLabel extends StatelessWidget {
  final String text;
  const RingLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Text(text,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: .1)),
        ),
      );
}

/// Points of a circle on the map (for a dotted ring line).
List<LatLng> ringPoints(LatLng c, double meters, [int n = 120]) {
  final dLat = meters / 111200;
  final dLng = meters / (111200 * math.cos(c.latitude * math.pi / 180));
  return [
    for (int i = 0; i <= n; i++)
      LatLng(c.latitude + dLat * math.sin(2 * math.pi * i / n), c.longitude + dLng * math.cos(2 * math.pi * i / n)),
  ];
}
