import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'osm.dart';
import 'places.dart';

/// Open data besides OpenStreetMap:
///  • City of Chicago bike racks (Data Portal): the current list 2015–2026 + the older historical list.
///  • Divvy stations, live (GBFS feed): bikes and free docks right now.
class OpenDataService {
  static const _cityDatasets = {
    'hgdw-64h3': 'City of Chicago · racks 2015–2026',
    'cbyb-69xx': 'City of Chicago · racks (historical list)',
  };
  static const _cacheKey = 'city_racks_v1';
  static const _cacheDays = 3;
  static const _divvyRoot = 'https://gbfs.divvybikes.com/gbfs/gbfs.json';

  /// City racks (as OpenStreetMap-like elements, then places).
  final Map<String, Place> cityRacks = {};
  final List<Map<String, dynamic>> _cityRaw = [];

  /// Divvy stations with live numbers.
  final Map<String, Place> divvy = {};
  DateTime? divvyUpdated;
  String? lastError;

  // ───────────── City of Chicago ─────────────

  /// Loads the city racks: from the phone if they are fresh, otherwise from the Data Portal.
  /// Returns true when something was loaded.
  Future<bool> loadCityRacks({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      try {
        final s = prefs.getString(_cacheKey);
        if (s != null) {
          final j = jsonDecode(s) as Map<String, dynamic>;
          final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
          final list = (j['els'] as List).cast<Map<String, dynamic>>();
          _setCity(list);
          if (DateTime.now().difference(at).inDays < _cacheDays) return list.isNotEmpty;
        }
      } catch (_) {}
    }
    final all = <Map<String, dynamic>>[];
    for (final e in _cityDatasets.entries) {
      final uri = Uri.parse('https://data.cityofchicago.org/resource/${e.key}.geojson?\$limit=50000');
      try {
        final r = await http.get(uri).timeout(const Duration(seconds: 40));
        if (r.statusCode != 200) {
          debugPrint('City racks ${e.key}: ${r.statusCode}');
          continue;
        }
        final feats = (jsonDecode(utf8.decode(r.bodyBytes))['features'] as List? ?? []).cast<Map<String, dynamic>>();
        var n = 0;
        for (final f in feats) {
          final el = _fromFeature(f, e.key, e.value, n++);
          if (el != null) all.add(el);
        }
        debugPrint('City racks ${e.key}: ${feats.length}');
      } catch (err) {
        lastError = 'no connection to the Chicago Data Portal';
        debugPrint('City racks ${e.key} failed: $err');
      }
    }
    if (all.isEmpty) return cityRacks.isNotEmpty;
    final slim = _dedupe(all);
    _setCity(slim);
    try {
      await prefs.setString(_cacheKey, jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'els': slim}));
    } catch (_) {
      // too big for the browser storage: it is simply loaded again next time
    }
    return true;
  }

  void _setCity(List<Map<String, dynamic>> list) {
    _cityRaw
      ..clear()
      ..addAll(list);
    cityRacks.clear();
    for (final el in list) {
      final p = placeFromOsm(el);
      if (p != null) cityRacks[p.id] = p;
    }
  }

  /// Recalculates distances after the GPS position changed.
  void refreshDistances() => _setCity(List.of(_cityRaw));

  /// One GeoJSON feature of the portal → an element like the OpenStreetMap ones.
  /// The portal's column names are read loosely, so small changes there do not break the app.
  Map<String, dynamic>? _fromFeature(Map<String, dynamic> f, String ds, String source, int i) {
    final g = f['geometry'] as Map<String, dynamic>?;
    final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
    double? lat, lon;
    if (g != null) {
      var c = g['coordinates'];
      while (c is List && c.isNotEmpty && c.first is List) {
        c = c.first; // MultiPoint → first point
      }
      if (c is List && c.length >= 2) {
        lon = (c[0] as num).toDouble();
        lat = (c[1] as num).toDouble();
      }
    }
    lat ??= double.tryParse('${props['latitude'] ?? props['lat'] ?? ''}');
    lon ??= double.tryParse('${props['longitude'] ?? props['lon'] ?? props['lng'] ?? ''}');
    if (lat == null || lon == null || lat.abs() < 1 || lon.abs() < 1) return null;

    String? pick(bool Function(String k) test) {
      for (final e in props.entries) {
        final v = e.value;
        if (v == null || v is Map || v is List) continue;
        if (test(e.key.toLowerCase()) && '$v'.trim().isNotEmpty) return '$v'.trim();
      }
      return null;
    }

    final address = pick((k) => k.contains('address') || k == 'location' || k.contains('street'));
    final qty = pick((k) => k.contains('quantity') || k.contains('total') || k.contains('rack') && k.contains('num'));
    final year = pick((k) => k.contains('install') || k.contains('date') || k.contains('year'));
    final id = pick((k) => k == 'rackid' || k == 'rack_id' || k == 'id' || k == 'objectid') ?? '$i';
    final racks = int.tryParse((qty ?? '').split('.').first);
    return {
      'id': 'chi/$ds/$id',
      'lat': lat,
      'lon': lon,
      'tags': {
        'amenity': 'bicycle_parking',
        'bicycle_parking': 'stands',
        if (racks != null && racks > 0) 'capacity': '${racks * 2}', // one rack holds two bikes
        if (address != null) 'addr:street': _title(address),
        'fee': 'no',
        'source': source,
        if (year != null && year.length >= 4) 'installed': year.substring(0, 4),
      },
    };
  }

  /// The two lists overlap: keep one rack per ~10 m.
  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> all) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final el in all) {
      final k = '${((el['lat'] as num) * 9000).round()}:${((el['lon'] as num) * 9000).round()}';
      if (seen.add(k)) out.add(el);
    }
    return out;
  }

  static String _title(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  // ───────────── Divvy, live ─────────────

  /// Divvy stations with bikes and free docks right now (call again every minute or two).
  Future<bool> loadDivvy() async {
    try {
      final root = await http.get(Uri.parse(_divvyRoot)).timeout(const Duration(seconds: 15));
      if (root.statusCode != 200) return false;
      final data = jsonDecode(root.body)['data'] as Map<String, dynamic>;
      final feeds = ((data['en'] ?? data.values.first) as Map<String, dynamic>)['feeds'] as List;
      String? url(String name) =>
          feeds.cast<Map<String, dynamic>>().where((f) => f['name'] == name).map((f) => f['url'] as String).firstOrNull;
      final infoUrl = url('station_information'), statusUrl = url('station_status');
      if (infoUrl == null || statusUrl == null) return false;
      final res = await Future.wait([
        http.get(Uri.parse(infoUrl)).timeout(const Duration(seconds: 20)),
        http.get(Uri.parse(statusUrl)).timeout(const Duration(seconds: 20)),
      ]);
      final info = (jsonDecode(utf8.decode(res[0].bodyBytes))['data']['stations'] as List).cast<Map<String, dynamic>>();
      final status = {
        for (final s in (jsonDecode(utf8.decode(res[1].bodyBytes))['data']['stations'] as List).cast<Map<String, dynamic>>())
          '${s['station_id']}': s,
      };
      const d = Distance();
      divvy.clear();
      for (final s in info) {
        final id = '${s['station_id']}';
        final st = status[id];
        final lat = (s['lat'] as num?)?.toDouble(), lon = (s['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final bikes = (st?['num_bikes_available'] as num?)?.toInt() ?? 0;
        final ebikes = (st?['num_ebikes_available'] as num?)?.toInt() ?? 0;
        final docks = (st?['num_docks_available'] as num?)?.toInt() ?? 0;
        final working = st == null || (st['is_renting'] ?? 1) == 1 || st['is_renting'] == true;
        final reported = (st?['last_reported'] as num?)?.toInt();
        final pos = LatLng(lat, lon);
        final m = d(userPos, pos);
        final accepts = ebikes > 0 ? const [Vehicle.bike, Vehicle.ebike] : const [Vehicle.bike];
        divvy['divvy/$id'] = Place(
          id: 'divvy/$id',
          type: PlaceType.sharing,
          address: '${s['name'] ?? 'Divvy station'}',
          pos: pos,
          status: !working || bikes == 0 ? Status.full : (bikes <= 2 ? Status.almost : Status.free),
          count: '$bikes',
          age: _age(reported),
          accepts: accepts,
          distance: m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km',
          etaMin: {for (final v in accepts) v: etaMinutes(m, v)},
          operatorName: 'Divvy',
          operatorPrice: '\$1 unlock · \$0.18/min',
          osm: true,
          facts: [
            '$bikes bikes now',
            if (ebikes > 0) '$ebikes e-bikes',
            '$docks free docks',
            if (s['capacity'] != null) 'Capacity ${s['capacity']}',
            'Live · Divvy',
          ],
        );
      }
      divvyUpdated = DateTime.now();
      debugPrint('Divvy: ${divvy.length} stations live');
      return divvy.isNotEmpty;
    } catch (err) {
      debugPrint('Divvy failed: $err');
      return false;
    }
  }

  static String _age(int? epochSec) {
    if (epochSec == null) return '<5 min';
    final m = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochSec * 1000)).inMinutes;
    if (m < 5) return '<5 min';
    if (m < 15) return '<15 min';
    if (m < 60) return '<1 h';
    return '${m ~/ 60} h';
  }
}
