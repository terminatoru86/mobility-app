import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'places.dart';

/// Where the rider is right now (null if GPS is off or not allowed).
Future<LatLng?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}

class GeoResult {
  final String title;
  final String subtitle;
  final LatLng pos;
  const GeoResult(this.title, this.subtitle, this.pos);
}

/// Search any address, city or place in the United States.
/// First Photon (fast, search-as-you-type, forgives typos, biased to where you are),
/// then Nominatim if Photon finds nothing. Both use OpenStreetMap data.
///
/// Results come from your area first (about 50 km around you), nearest first;
/// only if nothing is found there do we search the whole country.
Future<List<GeoResult>> searchUs(String q, {LatLng? near}) async {
  q = q.trim();
  if (q.length < 3) return [];
  final c = near ?? userPos;
  // 1) your area only
  final local = '${(c.longitude - 0.6).toStringAsFixed(3)},${(c.latitude - 0.45).toStringAsFixed(3)},'
      '${(c.longitude + 0.6).toStringAsFixed(3)},${(c.latitude + 0.45).toStringAsFixed(3)}';
  var r = await _photon(q, c, local);
  if (r.isEmpty) r = await _nominatim(q, c, bounded: true);
  // 2) the whole country
  if (r.isEmpty) r = await _photon(q, c, '-125.0,24.0,-66.5,49.5');
  if (r.isEmpty) r = await _nominatim(q, c, bounded: false);
  const d = Distance();
  r.sort((a, b) => d(c, a.pos).compareTo(d(c, b.pos)));
  return r;
}

Future<List<GeoResult>> _photon(String q, LatLng? near, String bbox) async {
  final params = {
    'q': q,
    'limit': '10',
    'lang': 'en',
    'bbox': bbox,
  };
  if (near != null) {
    params['lat'] = near.latitude.toStringAsFixed(4);
    params['lon'] = near.longitude.toStringAsFixed(4);
  }
  try {
    final r = await http.get(Uri.https('photon.komoot.io', '/api/', params)).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return [];
    final feats = (jsonDecode(utf8.decode(r.bodyBytes))['features'] as List).cast<Map<String, dynamic>>();
    final out = <GeoResult>[];
    for (final f in feats) {
      final p = (f['properties'] as Map).cast<String, dynamic>();
      if ((p['countrycode'] as String?)?.toUpperCase() != 'US') continue;
      final c = f['geometry']['coordinates'] as List;
      final street = [p['housenumber'], p['street']].whereType<String>().join(' ');
      final name = p['name'] as String?;
      final title = (name != null && name.isNotEmpty) ? name : (street.isNotEmpty ? street : (p['city'] as String? ?? q));
      final sub = [
        if (name != null && street.isNotEmpty) street,
        p['city'],
        p['state'],
      ].whereType<String>().join(', ');
      out.add(GeoResult(title, sub, LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())));
      if (out.length == 6) break;
    }
    return out;
  } catch (_) {
    return [];
  }
}

Future<List<GeoResult>> _nominatim(String q, LatLng c, {required bool bounded}) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': q,
    'format': 'jsonv2',
    'countrycodes': 'us',
    'limit': '6',
    'viewbox': '${c.longitude - 0.6},${c.latitude + 0.45},${c.longitude + 0.6},${c.latitude - 0.45}',
    'bounded': bounded ? '1' : '0',
  });
  try {
    final r = await http
        .get(uri, headers: kIsWeb ? null : {'User-Agent': 'MOBIlity/0.1 (com.mobility.app)'})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    final list = (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
    return [
      for (final e in list)
        GeoResult(
          (e['name'] as String?)?.isNotEmpty == true ? e['name'] as String : (e['display_name'] as String).split(',').first,
          e['display_name'] as String,
          LatLng(double.parse(e['lat'] as String), double.parse(e['lon'] as String)),
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// City name for a point ("Madison, WI"), from OpenStreetMap (Nominatim). Null if it does not answer.
Future<String?> cityName(LatLng p) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'lat': p.latitude.toStringAsFixed(4),
    'lon': p.longitude.toStringAsFixed(4),
    'format': 'jsonv2',
    'zoom': '10',
    'addressdetails': '1',
  });
  try {
    final r = await http
        .get(uri, headers: kIsWeb ? null : {'User-Agent': 'MOBIlity/0.1 (com.mobility.app)'})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final a = (jsonDecode(utf8.decode(r.bodyBytes))['address'] as Map?) ?? {};
    final city = a['city'] ?? a['town'] ?? a['village'] ?? a['county'];
    const states = {
      'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR', 'California': 'CA', 'Colorado': 'CO',
      'Connecticut': 'CT', 'Delaware': 'DE', 'District of Columbia': 'DC', 'Florida': 'FL', 'Georgia': 'GA',
      'Hawaii': 'HI', 'Idaho': 'ID', 'Illinois': 'IL', 'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS',
      'Kentucky': 'KY', 'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD', 'Massachusetts': 'MA',
      'Michigan': 'MI', 'Minnesota': 'MN', 'Mississippi': 'MS', 'Missouri': 'MO', 'Montana': 'MT',
      'Nebraska': 'NE', 'Nevada': 'NV', 'New Hampshire': 'NH', 'New Jersey': 'NJ', 'New Mexico': 'NM',
      'New York': 'NY', 'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH', 'Oklahoma': 'OK',
      'Oregon': 'OR', 'Pennsylvania': 'PA', 'Rhode Island': 'RI', 'South Carolina': 'SC', 'South Dakota': 'SD',
      'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT', 'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA',
      'West Virginia': 'WV', 'Wisconsin': 'WI', 'Wyoming': 'WY',
    };
    final st = states[a['state']] ?? a['state'];
    if (city == null) return st?.toString();
    return st == null ? '$city' : '$city, $st';
  } catch (_) {
    return null;
  }
}
