import 'dart:convert';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// A public traffic camera (state DOT / city) with a live snapshot image.
class TrafficCamera {
  final LatLng pos;
  final String name, image, source;
  final double meters; // from the place asked about
  const TrafficCamera(this.pos, this.name, this.image, this.source, [this.meters = 0]);
}

/// Public traffic cameras shipped with the app (assets/osm/cameras.json.gz, made by the data build).
class Cameras {
  static List<List<dynamic>>? _rows;
  static Future<void>? _loading;

  static Future<void> _load() => _loading ??= () async {
        try {
          final bytes = await rootBundle.load('assets/osm/cameras.json.gz');
          final text = utf8.decode(const GZipDecoder().decodeBytes(bytes.buffer.asUint8List()));
          _rows = (jsonDecode(text) as List).cast<List<dynamic>>();
        } catch (e) {
          debugPrint('Cameras not loaded: $e');
          _rows = const [];
        }
      }();

  /// The nearest public camera within [maxMeters] of [p] (null if none).
  static Future<TrafficCamera?> nearest(LatLng p, {double maxMeters = 400}) async {
    await _load();
    const d = Distance();
    TrafficCamera? best;
    for (final r in _rows!) {
      final lat = (r[0] as num).toDouble(), lon = (r[1] as num).toDouble();
      if ((lat - p.latitude).abs() > 0.01 || (lon - p.longitude).abs() > 0.013) continue; // quick box first
      final m = d(p, LatLng(lat, lon));
      if (m <= maxMeters && (best == null || m < best.meters)) {
        best = TrafficCamera(LatLng(lat, lon), '${r[2]}', '${r[3]}', '${r[4]}', m);
      }
    }
    return best;
  }
}
