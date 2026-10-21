import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Mapillary: street-level photos all over the US (and bike racks found in them).
/// Client token of the MOBIlity app (made for apps, read-only).
const kMapillaryToken = 'MLY|27126179113747269|034251afe635aebc90b86891558364c6';

final Map<String, List<String>> _cache = {};

/// Up to [max] street photos taken within ~30 m of [p], nearest first (empty if none).
Future<List<String>> mapillaryPhotos(LatLng p, {int max = 4}) async {
  final key = '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
  final c = _cache[key];
  if (c != null) return c;
  const dLat = 0.00027; // ~30 m
  final dLng = dLat / 0.75;
  final uri = Uri.https('graph.mapillary.com', '/images', {
    'access_token': kMapillaryToken,
    'fields': 'id,thumb_1024_url,computed_geometry,captured_at',
    'bbox': '${p.longitude - dLng},${p.latitude - dLat},${p.longitude + dLng},${p.latitude + dLat}',
    'limit': '20',
  });
  try {
    final r = await http.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return _cache[key] = const [];
    final data = ((jsonDecode(r.body) as Map<String, dynamic>)['data'] as List? ?? []).cast<Map<String, dynamic>>();
    const d = Distance();
    double dist(Map<String, dynamic> e) {
      final g = (e['computed_geometry'] as Map?)?['coordinates'] as List?;
      if (g == null || g.length < 2) return 1e9;
      return d(p, LatLng((g[1] as num).toDouble(), (g[0] as num).toDouble()));
    }

    data.sort((a, b) {
      // nearest first; among equals, the newest
      final x = dist(a).compareTo(dist(b));
      return x != 0 ? x : ((b['captured_at'] as num?) ?? 0).compareTo((a['captured_at'] as num?) ?? 0);
    });
    return _cache[key] = [
      for (final e in data.take(max))
        if (e['thumb_1024_url'] != null) '${e['thumb_1024_url']}',
    ];
  } catch (e) {
    debugPrint('Mapillary failed: $e');
    return const [];
  }
}
