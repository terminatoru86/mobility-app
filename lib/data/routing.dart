import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One step of the directions, e.g. "Turn left onto W Madison St".
class RouteStep {
  final String text;
  final double meters;
  const RouteStep(this.text, this.meters);
}

class RouteResult {
  final List<LatLng> points;
  final double meters;
  final double seconds;
  final List<RouteStep> steps;
  const RouteResult(this.points, this.meters, this.seconds, this.steps);

  String get distance => meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
  String get duration {
    final m = (seconds / 60).round();
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  String get arrival {
    final t = DateTime.now().add(Duration(seconds: seconds.round()));
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// Bike route through [via] (2 or more points), on streets and bike paths.
/// Uses the free OSRM bike router of the OpenStreetMap community (FOSSGIS).
Future<RouteResult?> bikeRoute(List<LatLng> via) async {
  final coords = via.map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}').join(';');
  final uri = Uri.parse('https://routing.openstreetmap.de/routed-bike/route/v1/driving/$coords'
      '?overview=full&geometries=geojson&steps=true');
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      debugPrint('Route: server answered ${r.statusCode}');
      return null;
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final routes = j['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final pts = [
      for (final c in (route['geometry']['coordinates'] as List))
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    final steps = <RouteStep>[];
    for (final leg in route['legs'] as List) {
      for (final s in (leg['steps'] as List)) {
        steps.add(RouteStep(_stepText(s as Map<String, dynamic>), (s['distance'] as num).toDouble()));
      }
    }
    return RouteResult(pts, (route['distance'] as num).toDouble(), (route['duration'] as num).toDouble(), steps);
  } catch (e) {
    debugPrint('Route failed: $e');
    return null;
  }
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
