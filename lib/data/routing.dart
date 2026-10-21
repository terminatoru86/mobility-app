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
  /// Real climb / descent from the elevation service (null until it answers).
  int? realClimb, realDescent;

  /// Share of each kind of road from the map data (null until it answers).
  Map<String, double>? roadMix;

  /// Estimate while the services answer: quieter routes avoid bridges a little more.
  double get _hill => switch (label) { 'Quiet' => 0.75, 'Balanced' => 0.88, _ => 1.0 };
  int get climb => realClimb ?? (meters / 1000 * 6 * _hill).round();
  int get descent => realDescent ?? (meters / 1000 * 5.4 * _hill).round();
}

/// Up to [n] points spread evenly along the route.
List<LatLng> _sample(List<LatLng> pts, int n) {
  if (pts.length <= n) return pts;
  final step = (pts.length - 1) / (n - 1);
  return [for (int i = 0; i < n; i++) pts[(i * step).round()]];
}

/// Real climb and descent: heights of up to 100 points from Open-Meteo (free, no key).
Future<void> addElevation(RouteResult r) async {
  if (r.realClimb != null || r.points.length < 2) return;
  final pts = _sample(r.points, 100);
  final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
    'latitude': pts.map((p) => p.latitude.toStringAsFixed(5)).join(','),
    'longitude': pts.map((p) => p.longitude.toStringAsFixed(5)).join(','),
  });
  try {
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return;
    final h = [for (final v in (jsonDecode(res.body)['elevation'] as List)) (v as num).toDouble()];
    var up = 0.0, down = 0.0;
    for (int i = 1; i < h.length; i++) {
      final d = h[i] - h[i - 1];
      if (d > 0.5) up += d; // ignore tiny noise
      if (d < -0.5) down -= d;
    }
    r.realClimb = up.round();
    r.realDescent = down.round();
  } catch (e) {
    debugPrint('Elevation failed: $e');
  }
}

/// Real road types along the route, from the OpenStreetMap data of the free Valhalla server (FOSSGIS):
/// protected lanes / quiet streets / bike lanes / shared roads / main roads.
Future<void> addRoadMix(RouteResult r) async {
  if (r.roadMix != null || r.points.length < 2) return;
  final pts = _sample(r.points, 400);
  final body = jsonEncode({
    'shape': [for (final p in pts) {'lat': p.latitude, 'lon': p.longitude}],
    'costing': 'bicycle',
    'shape_match': 'map_snap',
    'filters': {
      'attributes': ['edge.use', 'edge.road_class', 'edge.cycle_lane', 'edge.length'],
      'action': 'include',
    },
  });
  try {
    final res = await http
        .post(Uri.parse('https://valhalla1.openstreetmap.de/trace_attributes'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return;
    final edges = (jsonDecode(utf8.decode(res.bodyBytes))['edges'] as List? ?? []).cast<Map<String, dynamic>>();
    final m = {'Protected lanes': 0.0, 'Quiet streets': 0.0, 'Bike lanes': 0.0, 'Shared roads': 0.0, 'Main roads': 0.0};
    for (final e in edges) {
      final len = (e['length'] as num?)?.toDouble() ?? 0;
      final use = '${e['use'] ?? ''}';
      final lane = '${e['cycle_lane'] ?? 'none'}';
      final cls = '${e['road_class'] ?? ''}';
      final k = (const ['cycleway', 'path', 'footway', 'mountain_bike', 'pedestrian'].contains(use) || lane == 'separated')
          ? 'Protected lanes'
          : lane == 'dedicated'
              ? 'Bike lanes'
              : lane == 'shared'
                  ? 'Shared roads'
                  : const ['motorway', 'trunk', 'primary', 'secondary'].contains(cls)
                      ? 'Main roads'
                      : 'Quiet streets';
      m[k] = m[k]! + len;
    }
    final total = m.values.fold<double>(0, (a, b) => a + b);
    if (total > 0) r.roadMix = {for (final e in m.entries) e.key: e.value / total};
  } catch (e) {
    debugPrint('Road types failed: $e');
  }
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

/// Fast, Balanced and Quiet as three real bike routes from Valhalla (OpenStreetMap data, FOSSGIS server):
/// Fast takes roads when they are quicker, Quiet keeps to bike paths and calm streets, Balanced in between.
Future<List<RouteResult>> _valhallaRoutes(List<LatLng> via) async {
  const modes = {'Fast': (0.75, 0.3), 'Balanced': (0.4, 0.5), 'Quiet': (0.05, 0.25)}; // (use_roads, use_hills)
  final out = <RouteResult>[];
  await Future.wait(modes.entries.map((m) async {
    final body = jsonEncode({
      'locations': [for (final p in via) {'lat': p.latitude, 'lon': p.longitude}],
      'costing': 'bicycle',
      'costing_options': {
        'bicycle': {'bicycle_type': 'Hybrid', 'use_roads': m.value.$1, 'use_hills': m.value.$2, 'cycling_speed': 16},
      },
      'directions_options': {'units': 'kilometers', 'language': 'en-US'},
    });
    try {
      final r = await http
          .post(Uri.parse('https://valhalla1.openstreetmap.de/route'), headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final trip = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['trip'] as Map<String, dynamic>;
      final pts = <LatLng>[];
      final steps = <RouteStep>[];
      for (final leg in (trip['legs'] as List).cast<Map<String, dynamic>>()) {
        final shape = _decodePolyline6(leg['shape'] as String);
        final base = pts.length;
        pts.addAll(shape);
        for (final mv in (leg['maneuvers'] as List).cast<Map<String, dynamic>>()) {
          final idx = (mv['begin_shape_index'] as num).toInt();
          final names = (mv['street_names'] as List?)?.cast<String>() ?? const [];
          steps.add(RouteStep(
            '${mv['instruction'] ?? ''}'.replaceAll(RegExp(r'\.$'), ''),
            names.isEmpty ? '' : names.first,
            ((mv['length'] as num?) ?? 0) * 1000,
            shape[idx.clamp(0, shape.length - 1)],
          ));
        }
        if (base > 0 && pts.length > base) pts.removeAt(base); // the joint point is in both legs
      }
      final sum = trip['summary'] as Map<String, dynamic>;
      out.add(RouteResult(pts, (sum['length'] as num).toDouble() * 1000, (sum['time'] as num).toDouble(), steps,
          label: m.key));
    } catch (e) {
      debugPrint('Valhalla ${m.key} failed: $e');
    }
  }));
  // keep Fast / Balanced / Quiet order; drop a route identical to another one
  const order = ['Fast', 'Balanced', 'Quiet'];
  out.sort((a, b) => order.indexOf(a.label).compareTo(order.indexOf(b.label)));
  final uniq = <RouteResult>[];
  for (final r in out) {
    if (uniq.any((u) => (u.meters - r.meters).abs() < 30 && (u.seconds - r.seconds).abs() < 20)) continue;
    uniq.add(r);
  }
  return uniq;
}

List<LatLng> _decodePolyline6(String s) {
  final out = <LatLng>[];
  int i = 0, lat = 0, lng = 0;
  while (i < s.length) {
    for (int k = 0; k < 2; k++) {
      int shift = 0, result = 0, b;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final d = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (k == 0) {
        lat += d;
      } else {
        lng += d;
      }
    }
    out.add(LatLng(lat / 1e6, lng / 1e6));
  }
  return out;
}

/// Up to three choices: Fast, Balanced and Quiet (Valhalla first, the OSRM bike router if it does not answer).
Future<List<RouteResult>> bikeRoutes(List<LatLng> via, {bool alternatives = true}) async {
  if (alternatives) {
    final v = await _valhallaRoutes(via);
    if (v.isNotEmpty) return v;
  }
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


/// A traffic light, stop sign or give-way sign on the route (from OpenStreetMap).
class RouteControl {
  final LatLng at;
  final String kind; // 'signals', 'stop', 'give_way'
  double along = 0; // metres from the start of the route
  RouteControl(this.at, this.kind);
}

/// Traffic lights, stop and give-way signs within ~12 m of the route (Overpass, free).
Future<List<RouteControl>> routeControls(List<LatLng> pts) async {
  if (pts.length < 2) return [];
  final step = math.max(1, (pts.length / 180).ceil());
  final line = <String>[];
  for (int i = 0; i < pts.length; i += step) {
    line.add('${pts[i].latitude.toStringAsFixed(5)},${pts[i].longitude.toStringAsFixed(5)}');
  }
  line.add('${pts.last.latitude.toStringAsFixed(5)},${pts.last.longitude.toStringAsFixed(5)}');
  final q = '[out:json][timeout:25];node(around:12,${line.join(',')})'
      '["highway"~"^(traffic_signals|stop|give_way)\$"];out;';
  for (final url in const ['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter']) {
    try {
      final r = await http.post(Uri.parse(url), body: {'data': q}).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) continue;
      final els = (jsonDecode(utf8.decode(r.bodyBytes))['elements'] as List).cast<Map<String, dynamic>>();
      final out = <RouteControl>[];
      for (final e in els) {
        final h = '${(e['tags'] as Map?)?['highway']}';
        out.add(RouteControl(LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()),
            h == 'traffic_signals' ? 'signals' : h));
      }
      // order along the route; lights a few metres apart on one crossing count once
      for (final c in out) {
        c.along = projectOnRoute(c.at, pts).$2;
      }
      out.sort((a, b) => a.along.compareTo(b.along));
      final merged = <RouteControl>[];
      for (final c in out) {
        if (merged.isNotEmpty && merged.last.kind == c.kind && c.along - merged.last.along < 35) continue;
        merged.add(c);
      }
      return merged;
    } catch (e) {
      debugPrint('Route controls failed at $url: $e');
    }
  }
  return [];
}
