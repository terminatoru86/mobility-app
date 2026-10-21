import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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
Future<List<GeoResult>> searchUs(String q, {LatLng? near}) async {
  q = q.trim();
  if (q.length < 3) return [];
  final r = await _photon(q, near);
  if (r.isNotEmpty) return r;
  return _nominatim(q);
}

Future<List<GeoResult>> _photon(String q, LatLng? near) async {
  final params = {
    'q': q,
    'limit': '10',
    'lang': 'en',
    'bbox': '-125.0,24.0,-66.5,49.5', // the lower 48 states
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

Future<List<GeoResult>> _nominatim(String q) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': q,
    'format': 'jsonv2',
    'countrycodes': 'us',
    'limit': '6',
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
