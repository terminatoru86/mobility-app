import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'place_db.dart';
import 'places.dart';

/// City-hall lists already inside the offline packs (no need to download them again).
final Set<String> packedCities = {};

List<dynamic> _decodeList(String s) => jsonDecode(s) as List<dynamic>;

/// The free OpenStreetMap servers allow very few requests at once from one phone:
/// all our requests wait in one line, and a "too many requests" answer waits and tries again.
Future<void> _line = Future.value();

Future<http.Response> _overpass(String url, String query, Duration timeout, {bool queue = true}) {
  Future<http.Response> run() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final r = await http.post(Uri.parse(url), body: {'data': query}).timeout(timeout);
      if (r.statusCode != 429 && r.statusCode != 504) return r;
      debugPrint('Overpass busy (${r.statusCode}), waiting…');
      await Future.delayed(Duration(seconds: 6 * (attempt + 1)));
    }
    return http.Response('busy', 429);
  }

  if (!queue) return run(); // what is on the screen does not wait behind the region pieces
  final job = _line.then((_) => run());
  _line = job.then((_) {}, onError: (_) {});
  return job;
}

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
    final query = '[out:json][timeout:60];('
        'nwr["amenity"="bicycle_parking"]($bbox);'
        'nwr["amenity"="bicycle_repair_station"]($bbox);'
        'nwr["amenity"="compressed_air"]($bbox);'
        'nwr["amenity"="bicycle_wash"]($bbox);'
        'nwr["amenity"="bicycle_rental"]($bbox);'
        'nwr["shop"="bicycle"]($bbox);'
        'nwr["amenity"="charging_station"]["bicycle"="yes"]($bbox);'
        ');out center tags;';

    for (final url in _endpoints) {
      try {
        final r = await _overpass(url, query, const Duration(seconds: 60), queue: false); // the screen goes first
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

  // ───────── the whole region: every place within 100 miles, piece by piece ─────────

  static const _tile = 0.5; // degrees (~55 x 40 km)
  static const _tileDays = 14;
  static const _keep = {
    'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name', 'brand',
    'network', 'operator', 'shop', 'bicycle', 'bicycle_rental', 'opening_hours', 'phone', 'contact:phone', 'website',
    'contact:website', 'addr:housenumber', 'addr:street', 'service:bicycle:repair', 'service:bicycle:pump',
    'service:bicycle:tools', 'service:bicycle:stand', 'service:bicycle:chain_tool', 'service:bicycle:rental',
    'service:bicycle:second_hand',
  };
  final Set<String> _tilesDone = {};

  // ── offline packs shipped with the app (assets/osm/tiles, built by tool/build_packs.py) ──
  Map<String, dynamic>? _packIndex;
  Future<Map<String, dynamic>?>? _packLoad;
  final Set<String> _packTilesDone = {};
  static const _packFreshDays = 30;

  /// The list of packs inside the app (null until the packs have been built once).
  Future<Map<String, dynamic>?> packIndex() => _packLoad ??= () async {
        try {
          final j = jsonDecode(await rootBundle.loadString('assets/osm/tiles/index.json')) as Map<String, dynamic>;
          if (j['at'] == null) return null;
          _packIndex = j;
          packedCities.addAll(((j['cities'] as List?) ?? const []).map((e) => '$e'));
          debugPrint('Packs: ${j['total']} places, ${(j['tiles'] as Map).length} tiles, from ${j['at']}');
          return j;
        } catch (_) {
          return null;
        }
      }();

  bool get packsFresh {
    final at = DateTime.tryParse('${_packIndex?['at']}');
    return at != null && DateTime.now().difference(at).inDays < _packFreshDays;
  }

  /// Version (hash) of a shipped piece, from the index (older indexes only have the count).
  String? _shippedHash(String key) {
    final v = (_packIndex?['tiles'] as Map?)?[key];
    return v is List && v.length > 1 ? '${v[1]}' : (v == null ? null : 'c$v');
  }

  final Map<String, Set<String>> _tileIds = {}; // piece -> its place ids (to replace a piece cleanly)

  void _putPiece(String key, List<dynamic> rows) {
    for (final id in _tileIds[key] ?? const <String>{}) {
      _raw.remove(id);
      places.remove(id);
    }
    final ids = <String>{};
    for (final r in rows) {
      final l = r as List;
      _add({'id': l[0], 'lat': l[1], 'lon': l[2], 'tags': l[3]});
      ids.add('${l[0]}');
    }
    _tileIds[key] = ids;
  }

  List<(int, int, double)> _degreePieces(LatLng c, double miles) {
    final rLat = miles * 1.609 / 111.2;
    final rLng = rLat / math.cos(c.latitude * math.pi / 180);
    final list = <(int, int, double)>[];
    for (int a = (c.latitude - rLat).floor(); a <= (c.latitude + rLat).floor(); a++) {
      for (int b = (c.longitude - rLng).floor(); b <= (c.longitude + rLng).floor(); b++) {
        list.add((a, b, _dist(c, LatLng(a + 0.5, b + 0.5))));
      }
    }
    list.sort((x, y) => x.$3.compareTo(y.$3));
    return list;
  }

  /// Instant: every place within [miles], nearest 1° piece first — from our database on the phone
  /// (pieces updated online) or else from the files shipped inside the app.
  Future<bool> _loadPacks(LatLng c, double miles, void Function() onPiece) async {
    final idx = await packIndex();
    final db = PlaceDb.i;
    await db.open();
    final have = ((idx?['tiles'] as Map?) ?? const {}).cast<String, dynamic>();
    var any = false;
    for (final (a, b, _) in _degreePieces(c, miles)) {
      final key = '${a}_$b';
      if (_packTilesDone.contains(key)) continue;
      String? text = await db.read(key); // updated online
      if (text == null && have.containsKey(key)) {
        try {
          text = await rootBundle.loadString('assets/osm/tiles/t_$key.json'); // shipped with the app
        } catch (_) {}
      }
      if (text == null && idx == null && db.hashOf(key) == null) continue; // nothing known here yet
      _packTilesDone.add(key);
      _done.add([a.toDouble(), b.toDouble(), a + 1.0, b + 1.0]); // the live map does not ask again here
      any = true;
      if (text == null) continue; // nothing for riders in this piece
      try {
        _putPiece(key, await compute(_decodeList, text));
        onPiece();
      } catch (err) {
        debugPrint('Pack $key failed: $err');
      }
    }
    return any;
  }

  /// Once a week: ask our data site which pieces changed and download only those (rider's area).
  Future<bool> _updateOnline(LatLng c, double miles, void Function() onPiece) async {
    final db = PlaceDb.i;
    await db.open();
    if (!db.checkDue) return true;
    try {
      final r = await http.get(Uri.parse('${PlaceDb.site}index.json')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return false;
      final remote = ((jsonDecode(r.body) as Map<String, dynamic>)['tiles'] as Map).cast<String, dynamic>();
      for (final (a, b, _) in _degreePieces(c, miles)) {
        final key = '${a}_$b';
        final v = remote[key];
        if (v == null) continue;
        final hash = v is List && v.length > 1 ? '${v[1]}' : 'c$v';
        if (hash == (db.hashOf(key) ?? _shippedHash(key))) continue; // already have this version
        final t = await http.get(Uri.parse('${PlaceDb.site}t_$key.json')).timeout(const Duration(seconds: 40));
        if (t.statusCode != 200) continue;
        final text = utf8.decode(t.bodyBytes);
        await db.write(key, text, hash);
        _putPiece(key, await compute(_decodeList, text));
        _packTilesDone.add(key);
        _done.add([a.toDouble(), b.toDouble(), a + 1.0, b + 1.0]);
        onPiece();
        debugPrint('Updated piece $key');
      }
      await db.checked();
      return true;
    } catch (e) {
      debugPrint('Online update failed: $e');
      return false;
    }
  }

  final Set<String> _regionsDone = {};
  bool regionBusy = false;

  /// Progress of the region load (pieces done / all), shown as a small pill on the map.
  final ValueNotifier<(int, int)?> regionProgress = ValueNotifier(null);

  /// Loads every rider place within [miles] of [c]: nearest pieces first, each piece saved on the phone
  /// for 2 weeks. [onPiece] is called after each piece (to redraw the map).
  Future<void> loadRegion(LatLng c, double miles, void Function() onPiece) async {
    final rk = '${(c.latitude * 4).round()}:${(c.longitude * 4).round()}';
    if (regionBusy || _regionsDone.contains(rk)) return;
    regionBusy = true;
    try {
      // 1) our database: on the phone / shipped inside the app — instant, no internet
      final local = await _loadPacks(c, miles, onPiece);
      // 2) once a week: only the pieces that changed, from our data site
      final online = await _updateOnline(c, miles, onPiece);
      if (local || online) {
        _regionsDone.add(rk);
        return; // our database covers it: the free OpenStreetMap servers are not needed
      }
      // 3) no database yet: ask OpenStreetMap piece by piece (saved on the phone 2 weeks)
      final rLat = miles * 1.609 / 111.2;
      final rLng = rLat / math.cos(c.latitude * math.pi / 180);
      final tiles = <(int, int, double)>[];
      for (int i = ((c.latitude - rLat) / _tile).floor(); i <= ((c.latitude + rLat) / _tile).floor(); i++) {
        for (int j = ((c.longitude - rLng) / _tile).floor(); j <= ((c.longitude + rLng) / _tile).floor(); j++) {
          final d = _dist(c, LatLng((i + 0.5) * _tile, (j + 0.5) * _tile)) / 1609;
          if (d <= miles + 25) tiles.add((i, j, d));
        }
      }
      tiles.sort((a, b) => a.$3.compareTo(b.$3));
      final prefs = await SharedPreferences.getInstance();
      void progress() {
        final done = tiles.where((t) => _tilesDone.contains('${t.$1}:${t.$2}')).length;
        regionProgress.value = done >= tiles.length ? null : (done, tiles.length);
      }

      progress();
      for (final (i, j, _) in tiles) {
        final key = '$i:$j';
        if (_tilesDone.contains(key)) continue;
        // 1) saved on the phone and fresh
        var ok = false;
        try {
          final saved = prefs.getString('osmt_$key');
          if (saved != null) {
            final js = jsonDecode(saved) as Map<String, dynamic>;
            if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(js['at'] as int)).inDays < _tileDays) {
              for (final e in (js['e'] as List)) {
                final l = e as List;
                _add({'id': l[0], 'lat': l[1], 'lon': l[2], 'tags': l[3]});
              }
              ok = true;
            }
          }
        } catch (_) {}
        // 2) from OpenStreetMap
        if (!ok) ok = await _fetchTile(i, j, key, prefs);
        if (ok) {
          _tilesDone.add(key);
          final s = i * _tile, w = j * _tile;
          _done.add([s, w, s + _tile, w + _tile]);
          onPiece();
        }
        progress();
      }
      // pieces the servers refused (busy): try them again, slowly
      for (int pass = 0; pass < 3; pass++) {
        final left = tiles.where((t) => !_tilesDone.contains('${t.$1}:${t.$2}')).toList();
        if (left.isEmpty) break;
        await Future.delayed(Duration(seconds: 20 * (pass + 1)));
        for (final (i, j, _) in left) {
          final key = '$i:$j';
          if (await _fetchTile(i, j, key, prefs)) {
            _tilesDone.add(key);
            final s = i * _tile, w = j * _tile;
            _done.add([s, w, s + _tile, w + _tile]);
            onPiece();
          }
          progress();
        }
      }
      if (tiles.every((t) => _tilesDone.contains('${t.$1}:${t.$2}'))) _regionsDone.add(rk);
    } finally {
      regionBusy = false;
      if (regionProgress.value != null && regionProgress.value!.$1 >= regionProgress.value!.$2) regionProgress.value = null;
    }
  }

  Future<bool> _fetchTile(int i, int j, String key, SharedPreferences prefs) async {
    final s = i * _tile, w = j * _tile;
    final bbox = '${s.toStringAsFixed(3)},${w.toStringAsFixed(3)},${(s + _tile).toStringAsFixed(3)},${(w + _tile).toStringAsFixed(3)}';
    final query = '[out:json][timeout:90];('
        'nwr["amenity"="bicycle_parking"]($bbox);'
        'nwr["amenity"="bicycle_repair_station"]($bbox);'
        'nwr["amenity"="compressed_air"]($bbox);'
        'nwr["amenity"="bicycle_wash"]($bbox);'
        'nwr["amenity"="bicycle_rental"]($bbox);'
        'nwr["shop"="bicycle"]($bbox);'
        'nwr["amenity"="charging_station"]["bicycle"="yes"]($bbox);'
        ');out center tags;';
    for (final url in _endpoints) {
      try {
        final r = await _overpass(url, query, const Duration(seconds: 100));
        if (r.statusCode != 200) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        final els = (jsonDecode(utf8.decode(r.bodyBytes))['elements'] as List).cast<Map<String, dynamic>>();
        final compact = <List<dynamic>>[];
        for (final el in els) {
          final e = _slim(el);
          if (e['lat'] == null) continue;
          final tags = Map<String, dynamic>.from(e['tags'] as Map)..removeWhere((k, _) => !_keep.contains(k));
          _add({'id': e['id'], 'lat': e['lat'], 'lon': e['lon'], 'tags': tags});
          compact.add([e['id'], e['lat'], e['lon'], tags]);
        }
        try {
          await prefs.setString('osmt_$key', jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'e': compact}));
        } catch (_) {
          // phone storage full (web): the piece is simply asked again next time
        }
        debugPrint('OSM region piece $key: ${els.length}');
        await Future.delayed(const Duration(milliseconds: 600)); // be gentle with the free servers
        return true;
      } catch (err) {
        debugPrint('OSM region piece $key failed at $url: $err');
      }
    }
    return false;
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
    if (_tilesDone.isNotEmpty) return; // the region pieces are saved on their own
    try {
      final p = await SharedPreferences.getInstance();
      final list = _raw.values.toList();
      await p.setString(_cacheKey, jsonEncode(list.length > _maxCached ? list.sublist(list.length - _maxCached) : list));
    } catch (_) {}
  }
}

const _dist = Distance(calculator: Haversine()); // fast enough for tens of thousands of places

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
      if (tag('bicycle_rental') == 'docking_station' ||
          const ['divvy', 'lime', 'bird', 'veo', 'spin', 'citi', 'bay wheels', 'capital bikeshare'].any(b.contains)) {
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
    if (tag('installed') != null) 'Installed ${tag('installed')}',
    if (tag('source') != null) tag('source')!,
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
