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

/// Search any address, city or place in the United States
/// (Nominatim, the free OpenStreetMap search).
Future<List<GeoResult>> searchUs(String q) async {
  if (q.trim().length < 3) return [];
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': q,
    'format': 'jsonv2',
    'countrycodes': 'us',
    'limit': '6',
  });
  try {
    final r = await http
        .get(uri, headers: kIsWeb ? null : {'User-Agent': 'MOBIlity/0.1 (com.mobility.app)'})
        .timeout(const Duration(seconds: 12));
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
