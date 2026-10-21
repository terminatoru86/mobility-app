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
