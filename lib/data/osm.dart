import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places.dart';

/// Real places for riders from OpenStreetMap, loaded through the free
/// Overpass API for the part of the map you are looking at.
/// Everything loaded is also saved on the phone, so the next start is instant.
class OsmService {
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  /// Cities shipped inside the app (made with tool/fetch_osm.dart): [file, s, w, n, e].
  static const _bundled = [
    ('assets/osm/chicago.json', 41.64, -87.94, 42.03, -87.52),
  ];
  static const _cacheKey = 'osm_cache_v1';
  static const _grid = 0.02; // ~2 km, areas are loaded in blocks of this size
  static const _maxSpan = 0.16; // never ask for more than ~16 x 16 km at once
  static const _maxCached = 5000;

  final Map<String, Map<String, dynamic>> _raw = {}; // osm id -> element
  final Map<String, Place> places = {};
  final List<List<double>> _done = []; // loaded areas [s, w, n, e]

  /// Why the last live load failed (shown on the map), null when all is fine.
  String? lastError;

  /// Cities shipped with the app: thousands of places, no internet needed.
  Future<void> loadBundled() async {
    for (final (file, s, w, n, e) in _bundled) {
      try {
        final list = (jsonDecode(await rootBundle.loadString(file)) as List).cast<Map<String, dynamic>>();
        if (list.isEmpty) continue;
        for (final el in list) {
          final p = placeFromOsm(el);
          if (p != null) places[p.id] = p;
        }
        _done.add([s, w, n, e]); // no need to ask the server inside this city
        debugPrint('OSM: ${list.length} places from $file');
      } catch (err) {
        debugPrint('OSM: could not read $file: $err');
      }
    }
  }

  /// Places saved on the phone from earlier runs (instant).
  Future<void> loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_cacheKey);
      if (s == null) return;
      for (final e in (jsonDecode(s) as List).cast<Map<String, dynamic>>()) {
        _add(e);
      }
    } catch (_) {
      // a broken cache is simply ignored
    }
  }

  /// Loads the area around the visible map. Returns true if something new came in.
  Future<bool> loadArea(double south, double west, double north, double east) async {
    // keep the request small: centre it and cap its size
    final cLat = (south + north) / 2, cLng = (west + east) / 2;
    final hLat = math.min((north - south) / 2, _maxSpan / 2);
    final hLng = math.min((east - west) / 2, _maxSpan / 2);
    final s = ((cLat - hLat) / _grid).floor() * _grid;
    final w = ((cLng - hLng) / _grid).floor() * _grid;
    final n = ((cLat + hLat) / _grid).ceil() * _grid;
    final e = ((cLng + hLng) / _grid).ceil() * _grid;
    if (_done.any((d) => d[0] <= s + 1e-9 && d[1] <= w + 1e-9 && d[2] >= n - 1e-9 && d[3] >= e - 1e-9)) {
      return false;
    }

    final bbox = '${s.toStringAsFixed(4)},${w.toStringAsFixed(4)},${n.toStringAsFixed(4)},${e.toStringAsFixed(4)}';
    final query = '[out:json][timeout:25];('
        'nwr["amenity"="bicycle_parking"]($bbox);'
        'nwr["amenity"="bicycle_repair_station"]($bbox);'
        'nwr["amenity"="compressed_air"]($bbox);'
        'nwr["amenity"="bicycle_wash"]($bbox);'
        'nwr["amenity"="bicycle_rental"]($bbox);'
        'nwr["shop"="bicycle"]($bbox);'
        'nwr["amenity"="charging_station"]["bicycle"="yes"]($bbox);'
        ');out center tags 3000;';

    for (final url in _endpoints) {
      try {
        final r = await http
            .post(Uri.parse(url), body: {'data': query})
            .timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) {
          lastError = 'server busy (${r.statusCode})';
          debugPrint('OSM: $url answered ${r.statusCode}');
          continue;
        }
        final els = (jsonDecode(utf8.decode(r.bodyBytes))['elements'] as List).cast<Map<String, dynamic>>();
        for (final el in els) {
          _add(_slim(el));
        }
        _done.add([s, w, n, e]);
        _save();
        lastError = null;
        debugPrint('OSM: ${els.length} places from $url');
        return true;
      } catch (err) {
        lastError = 'no connection to OpenStreetMap';
        debugPrint('OSM: $url failed: $err');
      }
    }
    return false;
  }

  // keep only what the app uses, so the saved cache stays small
  Map<String, dynamic> _slim(Map<String, dynamic> el) {
    final lat = el['lat'] ?? el['center']?['lat'];
    final lon = el['lon'] ?? el['center']?['lon'];
    return {'id': '${el['type']}/${el['id']}', 'lat': lat, 'lon': lon, 'tags': el['tags'] ?? {}};
  }

  /// Recalculates distances and arrival times after the GPS position changed.
  void refreshDistances() {
    for (final e in _raw.values.toList()) {
      _add(e);
    }
  }

  void _add(Map<String, dynamic> e) {
    final p = placeFromOsm(e);
    if (p == null) return;
    _raw[p.id] = e;
    places[p.id] = p;
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = _raw.values.toList();
      await p.setString(_cacheKey, jsonEncode(list.length > _maxCached ? list.sublist(list.length - _maxCached) : list));
    } catch (_) {}
  }
}

const _dist = Distance();

/// Turns an OpenStreetMap element into a MOBIlity place.
Place? placeFromOsm(Map<String, dynamic> e) {
  final lat = (e['lat'] as num?)?.toDouble();
  final lon = (e['lon'] as num?)?.toDouble();
  if (lat == null || lon == null) return null;
  final t = Map<String, dynamic>.from(e['tags'] as Map? ?? {});
  String? tag(String k) => t[k]?.toString();
  bool yes(String k) => tag(k) == 'yes';

  final amenity = tag('amenity');
  final brand = tag('brand') ?? tag('network') ?? tag('operator');
  PlaceType? type;
  String? operatorName;
  switch (amenity) {
    case 'bicycle_parking':
      final kind = tag('bicycle_parking') ?? '';
      if (tag('access') == 'private' || tag('access') == 'customers' || yes('fee')) {
        type = PlaceType.parkPrivate;
      } else if (yes('covered') || kind == 'building' || kind == 'shed') {
        type = PlaceType.parkCovered;
      } else if (const ['stands', 'wall_loops', 'rack', 'bollard', 'wide_stands', 'ground_slots'].contains(kind)) {
        type = PlaceType.rack;
      } else {
        type = PlaceType.parkOutdoor;
      }
    case 'bicycle_repair_station':
      type = PlaceType.selfService;
    case 'compressed_air':
      type = PlaceType.pump;
    case 'bicycle_wash':
      type = PlaceType.wash;
    case 'charging_station':
      type = PlaceType.charging;
    case 'bicycle_rental':
      final b = (brand ?? '').toLowerCase();
      if (const ['divvy', 'lime', 'bird', 'veo', 'spin', 'citi', 'bay wheels', 'capital bikeshare']
          .any(b.contains)) {
        type = PlaceType.sharing;
        operatorName = brand;
      } else {
        type = PlaceType.rent;
      }
  }
  if (type == null && tag('shop') == 'bicycle') {
    type = yes('service:bicycle:repair') ? PlaceType.service : PlaceType.shop;
  }
  if (type == null) return null;

  final pos = LatLng(lat, lon);
  final meters = _dist(userPos, pos);
  final street = [tag('addr:housenumber'), tag('addr:street')].whereType<String>().join(' ');
  final name = tag('name');
  final address = name ?? (street.isNotEmpty ? street : type.title);

  final facts = <String>[
    if (tag('capacity') != null) 'Capacity ${tag('capacity')}',
    if (yes('covered')) 'Covered',
    if (tag('fee') == 'no') 'Free',
    if (yes('fee')) 'Paid',
    if (yes('lit')) 'Lit',
    if (yes('service:bicycle:pump')) 'Pump',
    if (yes('service:bicycle:tools')) 'Tools',
    if (yes('service:bicycle:stand')) 'Repair stand',
    if (yes('service:bicycle:chain_tool')) 'Chain tool',
    if (yes('service:bicycle:repair')) 'Repairs',
    if (yes('service:bicycle:rental')) 'Rental',
    if (yes('service:bicycle:second_hand')) 'Second hand',
  ];

  final accepts = switch (type) {
    PlaceType.charging => const [Vehicle.ebike, Vehicle.scooter],
    PlaceType.sharing => const [Vehicle.bike, Vehicle.ebike, Vehicle.scooter],
    _ => const [Vehicle.bike, Vehicle.ebike, Vehicle.scooter],
  };

  // TEST DATA: until riders report, every real place gets a believable
  // status, free spots, ratings and reviews (always the same for the same place).
  final t0 = _TestData(e['id'].toString(), int.tryParse(tag('capacity') ?? ''), type);

  return Place(
    id: e['id'].toString(),
    type: type,
    address: address,
    pos: pos,
    status: type.isNeutral ? Status.neutral : t0.status,
    count: t0.count,
    age: t0.age,
    busy: t0.busy,
    reviews: t0.reviews,
    qa: t0.qa,
    tag: type == PlaceType.charging ? '⚡ Type 2' : (type == PlaceType.wash ? 'Automatic' : null),
    priceNow: type == PlaceType.parkPrivate ? '\$${(1 + t0.n % 3)}/h' : null,
    operatorPrice: type == PlaceType.sharing ? '\$1 unlock · \$0.${17 + t0.n % 20}/min' : null,
    accepts: accepts,
    distance: meters < 1000 ? '${(meters / 10).round() * 10} m' : '${(meters / 1000).toStringAsFixed(1)} km',
    etaMin: {for (final v in accepts) v: etaMinutes(meters, v)},
    hours: tag('opening_hours'),
    phone: tag('phone') ?? tag('contact:phone'),
    rating: t0.rating,
    reviewCount: t0.reviewCount,
    security: (type == PlaceType.parkCovered || type == PlaceType.parkPrivate)
        ? Security(
            cameras: (tag('surveillance') ?? 'no') != 'no',
            lighting: yes('lit'),
            access: tag('access') == 'customers' || tag('access') == 'private',
          )
        : null,
    operatorName: operatorName,
    osm: true,
    facts: facts,
    website: tag('website') ?? tag('contact:website'),
  );
}

/// Turn on/off the test statuses and ratings on real places.
const bool kTestData = true;

class _TestData {
  late final int n;
  late final Status status;
  late final String? count;
  late final String age;
  late final double rating;
  late final int reviewCount;
  late final List<Review> reviews;
  late final List<QA> qa;
  late final List<int> busy;

  static const _ages = ['<5 min', '12 min', '25 min', '40 min', '1 h', '2 h'];
  static const _texts = [
    'Always a free spot in the morning.',
    'Well lit, close to the train.',
    'Busy after 5 pm.',
    'Solid racks, felt safe leaving my bike.',
    'Easy to find, right by the entrance.',
    'Gets full on weekends.',
    'Friendly staff, quick fix.',
    'Clean and well kept.',
  ];
  static const _whens = ['today', 'yesterday', '3 days ago', '1 week ago', '2 weeks ago'];

  _TestData(String id, int? capacity, PlaceType type) {
    // FNV-1a hash: the same place always gets the same test values
    var h = 0x811c9dc5;
    for (final c in id.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    n = h;
    if (!kTestData) {
      status = Status.unknown;
      count = null;
      age = '';
      rating = 0;
      reviewCount = 0;
      reviews = const [];
      qa = const [];
      busy = const [];
      return;
    }
    final roll = h % 100;
    status = roll < 55
        ? Status.free
        : roll < 78
            ? Status.almost
            : roll < 90
                ? Status.full
                : Status.unknown;
    final cap = (capacity != null && capacity > 0) ? capacity : 4 + h % 14;
    count = switch (status) {
      Status.free => '${math.max(2, (cap * (0.4 + (h >> 3) % 50 / 100)).round())}',
      Status.almost => '${1 + (h >> 4) % 2}',
      _ => null,
    };
    age = status == Status.unknown ? '4 h' : _ages[(h >> 5) % 4];
    rating = 3.6 + ((h >> 6) % 14) / 10; // 3.6 - 4.9
    reviewCount = 3 + (h >> 7) % 120;
    reviews = [
      for (int k = 0; k < 3; k++)
        Review(rating >= 4.3 ? 5 - k % 2 : 4 - k % 2, _texts[((h >> (8 + k)) + k * 3) % _texts.length],
            _whens[(k + (h >> 9)) % _whens.length]),
    ];
    qa = const [
      QA('Can I leave my bike overnight?', 'Yes, riders say it is fine and well lit.'),
      QA('Is there room for cargo bikes?', 'Only at the end of the row.'),
    ];
    final peak = 8 + (h >> 10) % 4; // busiest slot
    busy = [
      for (int i = 0; i < 12; i++) math.max(8, 95 - (i - peak).abs() * 14 - (h >> (i % 8)) % 10),
    ];
  }
}

/// Rough minutes to get there, by vehicle (straight line + 30 % for streets).
int etaMinutes(double meters, Vehicle v) {
  final kmh = switch (v) {
    Vehicle.bike => 15.0,
    Vehicle.ebike => 22.0,
    Vehicle.scooter => 18.0,
    Vehicle.moped => 30.0,
    Vehicle.moto => 35.0,
  };
  return math.max(1, (meters * 1.3 / 1000 / kmh * 60).round());
}
