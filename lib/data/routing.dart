import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One step of the directions, e.g. "Turn left onto W Madison St".
class RouteStep {
  final String text;
  final String street;
  final double meters;
  final LatLng at; // where the maneuver happens
  const RouteStep(this.text, this.street, this.meters, this.at);
}

class RouteResult {
  final List<LatLng> points;
  final double meters;
  final double seconds;
  final List<RouteStep> steps;
  String label; // Fast / Balanced / Quiet
  RouteResult(this.points, this.meters, this.seconds, this.steps, {this.label = 'Fast'});

  String get distance => fmtDistance(meters);
  String get duration => fmtMinutes(seconds / 60);
  String get arrival => arrivalAt(seconds);

  /// Rough climb in metres (no elevation service yet): about 6 m per km on Chicago's flat streets.
  /// Quieter routes avoid the bridges and overpasses a little more.
  double get _hill => switch (label) { 'Quiet' => 0.75, 'Balanced' => 0.88, _ => 1.0 };
  int get climb => (meters / 1000 * 6 * _hill).round();
  int get descent => (meters / 1000 * 5.4 * _hill).round();
}

String fmtDistance(double m) => m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km';

String fmtMinutes(double min) {
  final m = min.round();
  return m < 60 ? '$m min' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

String arrivalAt(double seconds) {
  final t = DateTime.now().add(Duration(seconds: seconds.round()));
  return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

/// Seconds for the same route with another vehicle (the router gives bike time).
double secondsFor(double meters, String vehicle) {
  final kmh = switch (vehicle) {
    'scooter' => 18.0,
    'ebike' => 22.0,
    'moped' => 30.0,
    'moto' => 35.0,
    _ => 15.0,
  };
  return meters / 1000 / kmh * 3600;
}

const _router = 'https://routing.openstreetmap.de/routed-bike/route/v1/driving/';

/// Bike route through [via] (2 or more points), on streets and bike paths.
/// Uses the free OSRM bike router of the OpenStreetMap community (FOSSGIS).
Future<RouteResult?> bikeRoute(List<LatLng> via) async {
  final all = await bikeRoutes(via, alternatives: false);
  return all.isEmpty ? null : all.first;
}

/// Up to three choices: Fast, Balanced and Quiet.
Future<List<RouteResult>> bikeRoutes(List<LatLng> via, {bool alternatives = true}) async {
  final coords = via.map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}').join(';');
  final alt = alternatives && via.length == 2 ? '&alternatives=3' : '';
  final uri = Uri.parse('$_router$coords?overview=full&geometries=geojson&steps=true$alt');
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      debugPrint('Route: server answered ${r.statusCode}');
      return [];
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final routes = (j['routes'] as List? ?? []).cast<Map<String, dynamic>>();
    final out = <RouteResult>[for (final route in routes) _parse(route)];
    if (out.isEmpty) return out;
    // Fast = quickest; Quiet = the longest alternative (usually the calmer streets); Balanced in between.
    out.sort((a, b) => a.seconds.compareTo(b.seconds));
    if (out.length == 1) {
      out.first.label = 'Fast';
    } else if (out.length == 2) {
      out[0].label = 'Fast';
      out[1].label = 'Quiet';
    } else {
      out[0].label = 'Fast';
      out[1].label = 'Balanced';
      out[2].label = 'Quiet';
    }
    return out.take(3).toList();
  } catch (e) {
    debugPrint('Route failed: $e');
    return [];
  }
}

RouteResult _parse(Map<String, dynamic> route) {
  final pts = [
    for (final c in (route['geometry']['coordinates'] as List))
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  final steps = <RouteStep>[];
  for (final leg in route['legs'] as List) {
    for (final s in (leg['steps'] as List)) {
      final m = s as Map<String, dynamic>;
      final loc = (m['maneuver']['location'] as List);
      steps.add(RouteStep(
        _stepText(m),
        (m['name'] as String?)?.trim() ?? '',
        (m['distance'] as num).toDouble(),
        LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
      ));
    }
  }
  return RouteResult(pts, (route['distance'] as num).toDouble(), (route['duration'] as num).toDouble(), steps);
}

String _stepText(Map<String, dynamic> s) {
  final m = s['maneuver'] as Map<String, dynamic>;
  final type = m['type'] as String? ?? '';
  final mod = m['modifier'] as String?;
  final name = (s['name'] as String?)?.trim() ?? '';
  final onto = name.isEmpty ? '' : ' onto $name';
  switch (type) {
    case 'depart':
      return name.isEmpty ? 'Start riding' : 'Start on $name';
    case 'arrive':
      return 'You have arrived';
    case 'roundabout':
    case 'rotary':
      return 'Take the roundabout$onto';
    case 'continue':
    case 'new name':
      return name.isEmpty ? 'Continue straight' : 'Continue on $name';
    default:
      if (mod == null || mod == 'straight') return name.isEmpty ? 'Go straight' : 'Go straight$onto';
      if (mod == 'uturn') return 'Make a U-turn$onto';
      return 'Turn $mod$onto';
  }
}

const _d = Distance();

/// Shortest distance in metres from [p] to the route line, and how far along the route that point is.
(double off, double along) projectOnRoute(LatLng p, List<LatLng> pts) {
  var best = double.infinity;
  var bestAlong = 0.0;
  var acc = 0.0;
  for (int i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final seg = _d(a, b);
    // project in a local flat frame (good enough for a few hundred metres)
    final kx = math.cos(a.latitude * math.pi / 180);
    final ax = a.longitude * kx, ay = a.latitude, bx = b.longitude * kx, by = b.latitude;
    final px = p.longitude * kx, py = p.latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0).toDouble();
    final q = LatLng(ay + dy * t, (ax + dx * t) / kx);
    final dist = _d(p, q);
    if (dist < best) {
      best = dist;
      bestAlong = acc + seg * t;
    }
    acc += seg;
  }
  return (best, bestAlong);
}

/// Point at [meters] along the route (used by the ride simulator).
LatLng pointAlong(List<LatLng> pts, double meters) {
  var left = meters;
  for (int i = 0; i < pts.length - 1; i++) {
    final seg = _d(pts[i], pts[i + 1]);
    if (left <= seg && seg > 0) {
      final t = left / seg;
      return LatLng(pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * t,
          pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * t);
    }
    left -= seg;
  }
  return pts.last;
}

/// Walking path between two points (for the dotted line to a bike rack).
/// Falls back to a straight line if the foot router does not answer.
Future<List<LatLng>> footPath(LatLng a, LatLng b) async {
  final uri = Uri.parse('https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
      '${a.longitude.toStringAsFixed(6)},${a.latitude.toStringAsFixed(6)};'
      '${b.longitude.toStringAsFixed(6)},${b.latitude.toStringAsFixed(6)}?overview=full&geometries=geojson');
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      final routes = (jsonDecode(r.body)['routes'] as List?) ?? [];
      if (routes.isNotEmpty) {
        return [
          for (final c in (routes.first['geometry']['coordinates'] as List))
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ];
      }
    }
  } catch (_) {}
  return [a, b];
}

/// Compass bearing in degrees from a to b.
double bearing(LatLng a, LatLng b) => _d.bearing(a, b);
