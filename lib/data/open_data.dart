import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'osm.dart';
import 'places.dart';

/// One city's official list of bike racks (open data portal of the city hall).
class CitySource {
  final String key;
  final String city;
  final String label; // shown in the place sheet
  final double s, w, n, e; // area of the city
  final String? socrata; // "domain/datasetId"
  final String? arcgis; // FeatureServer / MapServer layer URL
  final String? where; // ArcGIS filter (falls back to all rows if the server refuses it)
  final String amenity; // what the list holds, as in OpenStreetMap
  final String? hubItem; // ArcGIS Online item id: its service address is looked up when needed
  final int layer; // layer of that item's service
  final bool national; // covers the whole US: only the part around the map is asked for
  final String level; // 'city', 'county', 'campus', 'region', 'state', 'national'
  const CitySource(this.key, this.city, this.label, this.s, this.w, this.n, this.e,
      {this.socrata,
      this.arcgis,
      this.where,
      this.amenity = 'bicycle_parking',
      this.hubItem,
      this.layer = 0,
      this.national = false,
      this.level = 'city'});

  bool near(LatLng p, [double margin = 0.25]) =>
      national ||
      p.latitude >= s - margin && p.latitude <= n + margin && p.longitude >= w - margin && p.longitude <= e + margin;
}

/// City halls that publish their bike racks (checked October 2026).
/// The rest of the US is covered by OpenStreetMap.
const kCitySources = [
  CitySource('chi-now', 'Chicago', 'City of Chicago · racks 2015–2026', 41.64, -87.94, 42.03, -87.52,
      socrata: 'data.cityofchicago.org/hgdw-64h3'),
  CitySource('chi-old', 'Chicago', 'City of Chicago · racks (historical list)', 41.64, -87.94, 42.03, -87.52,
      socrata: 'data.cityofchicago.org/cbyb-69xx'),
  CitySource('nyc', 'New York', 'NYC DOT · bicycle parking', 40.49, -74.26, 40.92, -73.70,
      socrata: 'data.cityofnewyork.us/592z-n7dk'),
  CitySource('sf', 'San Francisco', 'SFMTA · bicycle parking racks', 37.70, -122.52, 37.83, -122.35,
      socrata: 'data.sf.gov/hn4j-6fx5'),
  CitySource('sea', 'Seattle', 'SDOT · bicycle racks', 47.49, -122.44, 47.74, -122.23,
      arcgis: 'https://services.arcgis.com/ZOyb2t4B0UYuYNYH/arcgis/rest/services/Bicycle_Racks_CDL/FeatureServer/0',
      where: "CURRENT_STATUS IN ('INSVC','PLNRECON')"),
  CitySource('dc', 'Washington DC', 'DDOT · public bike racks', 38.79, -77.12, 39.00, -76.90,
      arcgis: 'https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/Transportation_Bikes_Trails_WebMercator/MapServer/168'),
  CitySource('pdx', 'Portland', 'PBOT · bicycle parking', 45.43, -122.84, 45.65, -122.47,
      arcgis: 'https://www.portlandmaps.com/od/rest/services/COP_OpenData_Transportation/MapServer/62'),
  CitySource('pdx-areas', 'Portland', 'PBOT · bike corrals', 45.43, -122.84, 45.65, -122.47,
      arcgis: 'https://www.portlandmaps.com/od/rest/services/COP_OpenData_Transportation/MapServer/219'),
  CitySource('cam', 'Cambridge MA', 'City of Cambridge · bike racks', 42.35, -71.16, 42.41, -71.06,
      arcgis: 'https://gis.cambridgema.gov/arcgis/rest/services/CDDEmbeddedLayers/MapServer/199'),
  CitySource('sj', 'San Jose', 'City of San José · bike racks', 37.12, -122.05, 37.47, -121.58,
      arcgis: 'https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/MapServer/417'),
  CitySource('arl', 'Arlington VA', 'Arlington County · bike & scooter corrals', 38.82, -77.17, 38.94, -77.03,
      arcgis: 'https://arlgis.arlingtonva.us/arcgis/rest/services/Open_Data/od_Transportation_Layers/MapServer/2'),
  CitySource('hnl', 'Honolulu', 'City of Honolulu · bike racks', 21.25, -158.30, 21.72, -157.64,
      socrata: 'data.honolulu.gov/ab7c-s2jr'),
  CitySource('atx-fixit', 'Austin', 'City of Austin · Bike Fix-It stations', 30.10, -97.94, 30.52, -97.56,
      socrata: 'data.austintexas.gov/cvnz-fq2z', amenity: 'bicycle_repair_station'),
  // ── added Oct 21 2026: more cities, counties, campuses, national ──
  CitySource('la', 'Los Angeles', 'City of Los Angeles · bike racks', 33.70, -118.67, 34.34, -118.15,
      hubItem: '3b022cced9704108af157d3d5eedb268', layer: 2),
  CitySource('det', 'Detroit', 'City of Detroit · bike parking (Detroit Greenways Coalition)', 42.25, -83.29, 42.45, -82.91,
      hubItem: '88f5f270fbf64e818dc391e143cd96ab'),
  CitySource('det-fix', 'Detroit', 'Detroit Greenways Coalition · bike repair stations', 42.25, -83.29, 42.45, -82.91,
      hubItem: '3e586ac317bc4c4a829bc789ea599c36', layer: 1, amenity: 'bicycle_repair_station'),
  CitySource('lnk', 'Lincoln NE', 'City of Lincoln · bike racks', 40.71, -96.82, 40.90, -96.58,
      hubItem: '642f7cf1c3cd45b4979992de6d4bfa7c'),
  CitySource('livermore', 'Livermore CA', 'City of Livermore · public bike racks', 37.64, -121.84, 37.73, -121.69,
      hubItem: '6fbac05278b9406e921932d6724803d7'),
  CitySource('gso', 'Greensboro NC', 'Greensboro DOT · bike racks', 35.98, -79.95, 36.17, -79.67,
      arcgis: 'https://gis.greensboro-nc.gov/arcgis/rest/services/Transportation/BIPed_Inventory_MS/MapServer/1'),
  CitySource('mono', 'Mono County CA', 'Mono County · bike racks', 37.46, -119.65, 38.71, -117.83,
      arcgis: 'https://gis.mono.ca.gov/webgis/rest/services/OpenData/FacilitiesInfrastructure/MapServer/3', level: 'county'),
  CitySource('ufl', 'Gainesville FL', 'University of Florida · bike racks', 29.62, -82.38, 29.66, -82.33,
      arcgis: 'https://gis.ufl.edu/campusserver/rest/services/Bike_Rack_Locations/MapServer/0', level: 'campus'),
  CitySource('ncsu', 'Raleigh NC', 'NC State University · bike racks', 35.76, -78.70, 35.80, -78.65,
      arcgis: 'https://gismaps.oit.ncsu.edu/arcgis/rest/services/Transportation/Transportation_BikeRacks/MapServer/0',
      level: 'campus'),
  CitySource('cornell', 'Ithaca NY', 'Cornell University · bike racks', 42.43, -76.50, 42.46, -76.46,
      arcgis: 'https://gis.fcs.cornell.edu/arcgis/rest/services/Production/Landscape_Features/MapServer/2', level: 'campus'),
  CitySource('usu', 'Logan UT', 'Utah State University · bike racks', 41.73, -111.83, 41.76, -111.80,
      arcgis: 'https://facpdcws.aggies.usu.edu/server/rest/services/Bikes/Bike_Racks/MapServer/0', level: 'campus'),
  // ── added Oct 21 2026 (2): campuses, Nashville, Philadelphia ──
  CitySource('asu', 'Tempe AZ', 'Arizona State University · bike parking', 33.40, -111.95, 33.44, -111.91,
      arcgis: 'https://gis.m.asu.edu/server/rest/services/Campus/CampusBike/MapServer/0', level: 'campus'),
  CitySource('asu-fix', 'Tempe AZ', 'Arizona State University · bike repair', 33.40, -111.95, 33.44, -111.91,
      arcgis: 'https://gis.m.asu.edu/server/rest/services/Campus/CampusBike/MapServer/1',
      amenity: 'bicycle_repair_station', level: 'campus'),
  CitySource('uaz-fix', 'Tucson AZ', 'University of Arizona · bike repair', 32.22, -110.97, 32.25, -110.93,
      arcgis: 'https://services.maps.arizona.edu/pdc/rest/services/PTSBlueprintNonEdits/MapServer/501',
      amenity: 'bicycle_repair_station', level: 'campus'),
  CitySource('uga', 'Athens GA', 'University of Georgia · bike racks', 33.92, -83.39, 33.96, -83.36,
      arcgis: 'https://maps.itos.uga.edu/arcgis/rest/services/OUA/UGA_CampusMap_Base/MapServer/5', level: 'campus'),
  CitySource('unc', 'Chapel Hill NC', 'UNC Chapel Hill · bike racks', 35.89, -79.07, 35.92, -79.03,
      arcgis: 'https://gismaps.unc.edu/ArcGIS/rest/services/Features/MapServer/33', level: 'campus'),
  CitySource('bna', 'Nashville TN', 'Nashville · bike racks', 35.97, -87.05, 36.40, -86.52,
      arcgis: 'https://services3.arcgis.com/58WV6GqBWodG9Kll/ArcGIS/rest/services/Bike_Racks_Nashville/FeatureServer/0'),
  CitySource('phl', 'Philadelphia', 'City of Philadelphia · bike racks (2012, via PASDA)', 39.87, -75.28, 40.14, -74.96,
      arcgis: 'https://maps.pasda.psu.edu/arcgis/rest/services/pasda/CityPhilly/MapServer/23'),
  // USDOT NTAD bikeshare layer: now asks for a token (Oct 2026), removed; live GBFS covers the docks.
  CitySource('carmel', 'Carmel IN', 'City of Carmel · bike racks', 39.92, -86.24, 40.03, -86.04,
      arcgis: 'https://carmelgis.carmel.in.gov/arcserver/rest/services/DOCS/Bike_Racks/FeatureServer/0'),
];

/// A bike / scooter share system from the public GBFS list (MobilityData), with its city.
class ShareSystem {
  final String name, location, url;
  final LatLng at;
  ShareSystem(this.name, this.location, this.url, this.at);
  String get operator {
    final n = name.toLowerCase();
    for (final o in const ['Lime', 'Bird', 'Spin', 'Veo', 'Divvy', 'Citi Bike', 'Bluebikes', 'Capital Bikeshare', 'Bay Wheels',
      'BIKETOWN', 'Metro Bike', 'Indego', 'Nice Ride', 'CoGo', 'BCycle', 'Lyft']) {
      if (n.contains(o.toLowerCase())) return o;
    }
    return name;
  }
}

/// Open data besides OpenStreetMap, loaded only for the area you are looking at:
///  • official city bike-rack lists (city halls' open data portals),
///  • every public bikeshare / scooter system in the US, live (GBFS).
class OpenDataService {
  static const _cacheDays = 3;
  static const _maxCache = 1500000; // characters; larger lists are simply loaded again next time
  static const _systemsKm = 35.0; // share systems whose city is this close
  static const _maxFloating = 300; // free-floating bikes/scooters shown at once

  final Map<String, Place> cityRacks = {};
  final Map<String, List<Map<String, dynamic>>> _raw = {}; // source key -> elements
  final Set<String> _tried = {};

  final Map<String, Place> sharing = {};
  final Set<String> liveOperators = {};
  List<ShareSystem>? _systems;
  final Map<String, (String?, String?, String?)> _feeds = {}; // system url -> (info, status, vehicles)
  List<ShareSystem> _active = [];
  String? lastError;

  // ───────────── city halls ─────────────

  /// Loads the city lists around [at] that are not loaded yet. Returns true when something new came in.
  Future<bool> loadCitiesAround(LatLng at) async {
    var changed = false;
    for (final src in kCitySources) {
      if (!src.near(at)) continue;
      if (packedCities.contains(src.key)) continue; // already inside the offline packs
      // national lists: one piece of ~45 x 45 km around the map at a time
      final cell = src.national ? '@${(at.latitude / 0.4).floor()}:${(at.longitude / 0.4).floor()}' : '';
      final key = '${src.key}$cell';
      if (_tried.contains(key)) continue;
      _tried.add(key);
      final els = await _cached(key) ?? await _download(src, key, src.national ? at : null);
      if (els == null || els.isEmpty) continue;
      _raw[key] = els;
      _addCity(els);
      changed = true;
      debugPrint('City data ${src.key}: ${els.length} racks');
    }
    return changed;
  }

  void _addCity(List<Map<String, dynamic>> els) {
    final seen = <String>{for (final p in cityRacks.values) _cell(p.pos.latitude, p.pos.longitude)};
    for (final el in els) {
      // the lists of one city overlap: one rack per ~10 m
      if (!seen.add(_cell(el['lat'] as num, el['lon'] as num))) continue;
      final p = placeFromOsm(el);
      if (p != null) cityRacks[p.id] = p;
    }
  }

  static String _cell(num lat, num lon) => '${(lat * 9000).round()}:${(lon * 9000).round()}';

  /// Recalculates distances after the GPS position changed.
  void refreshDistances() {
    cityRacks.clear();
    for (final els in _raw.values) {
      _addCity(els);
    }
  }

  Future<List<Map<String, dynamic>>?> _cached(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('city_$key');
      if (s == null) return null;
      final j = jsonDecode(s) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      if (DateTime.now().difference(at).inDays >= _cacheDays) return null;
      return (j['els'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _download(CitySource src, String key, LatLng? around) async {
    List<Map<String, dynamic>>? els;
    try {
      if (src.socrata != null) {
        els = await _socrata(src);
      } else {
        final url = src.arcgis ?? await _itemService(src);
        if (url != null) els = await _arcgis(src, url, around);
      }
    } catch (err) {
      lastError = 'no connection to ${src.city} open data';
      debugPrint('City data ${src.key} failed: $err');
    }
    if (els == null || els.isEmpty) return els;
    try {
      final s = jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'els': els});
      if (s.length <= _maxCache) await (await SharedPreferences.getInstance()).setString('city_$key', s);
    } catch (_) {}
    return els;
  }

  Future<List<Map<String, dynamic>>> _socrata(CitySource src) async {
    final i = src.socrata!.indexOf('/');
    final uri = Uri.parse('https://${src.socrata!.substring(0, i)}/resource/${src.socrata!.substring(i + 1)}.geojson'
        '?\$limit=60000');
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw 'answered ${r.statusCode}';
    final feats = (jsonDecode(utf8.decode(r.bodyBytes))['features'] as List? ?? []).cast<Map<String, dynamic>>();
    final out = <Map<String, dynamic>>[];
    var n = 0;
    for (final f in feats) {
      final g = f['geometry'] as Map<String, dynamic>?;
      var c = g?['coordinates'];
      while (c is List && c.isNotEmpty && c.first is List) {
        c = c.first; // MultiPoint → first point
      }
      final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
      final el = _element(src, props, c is List && c.length >= 2 ? (c[1] as num).toDouble() : null,
          c is List && c.length >= 2 ? (c[0] as num).toDouble() : null, n++);
      if (el != null) out.add(el);
    }
    return out;
  }

  /// The service address of an ArcGIS Online item (public items only).
  Future<String?> _itemService(CitySource src) async {
    if (src.hubItem == null) return null;
    final r = await http
        .get(Uri.parse('https://www.arcgis.com/sharing/rest/content/items/${src.hubItem}?f=json'))
        .timeout(const Duration(seconds: 20));
    final url = (jsonDecode(r.body) as Map<String, dynamic>)['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final u = url.replaceAll(RegExp(r'/+$'), '');
    return RegExp(r'(FeatureServer|MapServer)$').hasMatch(u) ? '$u/${src.layer}' : u;
  }

  /// ArcGIS REST (FeatureServer or MapServer): plain JSON in WGS84, page by page.
  /// [around]: for national layers, only a box of about 45 x 45 km around that point.
  Future<List<Map<String, dynamic>>> _arcgis(CitySource src, String url, LatLng? around) async {
    final out = <Map<String, dynamic>>[];
    var where = src.where ?? '1=1';
    var offset = 0, n = 0;
    for (int page = 0; page < 60; page++) {
      final uri = Uri.parse('$url/query').replace(queryParameters: {
        if (around != null) ...{
          'geometry': '${around.longitude - 0.25},${around.latitude - 0.2},${around.longitude + 0.25},${around.latitude + 0.2}',
          'geometryType': 'esriGeometryEnvelope',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
        },
        'where': where,
        'outFields': '*',
        'outSR': '4326',
        'returnGeometry': 'true',
        'f': 'json',
        'resultOffset': '$offset',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 40));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['error'] != null) {
        if (where != '1=1') {
          where = '1=1'; // the filter's field does not exist any more: take everything
          page--;
          continue;
        }
        if (offset > 0) break; // server without paging: keep the first page
        throw '${j['error']}';
      }
      final feats = (j['features'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final f in feats) {
        final g = f['geometry'] as Map<String, dynamic>?;
        final el = _element(src, Map<String, dynamic>.from(f['attributes'] as Map? ?? {}), (g?['y'] as num?)?.toDouble(),
            (g?['x'] as num?)?.toDouble(), n++);
        if (el != null) out.add(el);
      }
      if (feats.isEmpty || j['exceededTransferLimit'] != true) break;
      offset += feats.length;
    }
    return out;
  }

  /// One row of a city list → an element like the OpenStreetMap ones (column names are read loosely).
  Map<String, dynamic>? _element(CitySource src, Map<String, dynamic> props, double? lat, double? lon, int i) {
    final low = {for (final e in props.entries) e.key.toLowerCase(): e.value};
    lat ??= double.tryParse('${low['latitude'] ?? low['lat'] ?? low['y'] ?? ''}');
    lon ??= double.tryParse('${low['longitude'] ?? low['lon'] ?? low['long'] ?? low['lng'] ?? low['x'] ?? ''}');
    if (lat == null || lon == null || lat.abs() < 1 || lon.abs() < 1 || lat.abs() > 90) return null;
    // racks taken out of service are not shown
    final status = '${low['status'] ?? low['current_status'] ?? ''}'.toLowerCase();
    if (status.contains('remov') || status.contains('retired') || status.contains('inactive')) return null;

    String? pick(bool Function(String k) test) {
      for (final e in low.entries) {
        final v = e.value;
        if (v == null || v is Map || v is List) continue;
        if (test(e.key) && '$v'.trim().isNotEmpty && '$v' != 'null') return '$v'.trim();
      }
      return null;
    }

    final address = pick((k) =>
        k.contains('address') || k == 'location' || k.contains('street') || k == 'site' || k.contains('loc_desc') || k == 'name');
    final spaces = pick((k) => k.contains('capacity') || k.contains('spaces') || k.contains('numspaces'));
    final racks = pick((k) => k.contains('totinstall') || k.contains('quantity') || k.contains('numberofracks') ||
        k == 'racks' || k.contains('num_racks') || k.contains('rack_count') || k.contains('numunits'));
    final when = pick((k) => k.contains('install') && !k.contains('tot') || k.contains('date_inst') || k == 'year');
    final covered = '${low['covered'] ?? ''}'.toLowerCase();
    final id = pick((k) => k.contains('rackid') || k == 'objectid' || k == 'fid' || k == 'assetid' || k == 'id') ?? '$i';
    int? toInt(String? s) => s == null ? null : double.tryParse(s)?.round();
    final cap = toInt(spaces) ?? (toInt(racks) == null ? null : toInt(racks)! * 2); // one rack holds two bikes
    var year = when;
    if (year != null && RegExp(r'^\d{12,}$').hasMatch(year)) {
      year = '${DateTime.fromMillisecondsSinceEpoch(int.parse(year)).year}'; // ArcGIS dates are milliseconds
    }
    return {
      'id': 'city/${src.key}/$id',
      'lat': lat,
      'lon': lon,
      'tags': {
        'amenity': src.amenity,
        if (src.amenity == 'bicycle_parking') 'bicycle_parking': 'stands',
        if (src.amenity == 'bicycle_repair_station') ...{'service:bicycle:pump': 'yes', 'service:bicycle:tools': 'yes'},
        if (cap != null && cap > 0 && src.amenity == 'bicycle_parking') 'capacity': '$cap',
        if (address != null) 'addr:street': _title(address),
        if (covered == 'yes' || covered == 'y' || covered == 'true') 'covered': 'yes',
        if (src.amenity == 'bicycle_parking') 'fee': 'no',
        if (src.amenity == 'bicycle_rental') 'bicycle_rental': 'docking_station',
        if (src.amenity == 'bicycle_rental') 'network': pick((k) => k.contains('system') || k.contains('network') || k.contains('operator')) ?? 'Bikeshare',
        'source': src.label,
        if (year != null && RegExp(r'^(19|20)\d\d').hasMatch(year)) 'installed': year.substring(0, 4),
      },
    };
  }

  static String _title(String s) => s.length < 4 || s != s.toUpperCase()
      ? s
      : s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  // ───────────── bikeshare & scooters, live (GBFS) ─────────────

  Future<List<ShareSystem>> _allSystems() async {
    if (_systems != null) return _systems!;
    try {
      final list = (jsonDecode(await rootBundle.loadString('assets/osm/gbfs_us.json')) as List).cast<Map<String, dynamic>>();
      _systems = [
        for (final s in list)
          ShareSystem(s['n'] as String, s['loc'] as String, s['url'] as String,
              LatLng((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble())),
      ];
    } catch (err) {
      debugPrint('GBFS list failed: $err');
      _systems = [];
    }
    return _systems!;
  }

  /// Picks the share systems of the city around [at] (call when the map moves to another city).
  Future<bool> chooseSystemsAround(LatLng at) async {
    const d = Distance();
    final near = (await _allSystems()).where((s) => d(at, s.at) / 1000 <= _systemsKm).toList();
    final same = near.length == _active.length && near.every(_active.contains);
    if (same) return false;
    _active = near;
    return refreshSharing();
  }

  /// Bikes, docks and scooters right now, for the systems around. Call again every minute or two.
  final Set<String> _dead = {};

  Future<bool> refreshSharing() async {
    if (_active.isEmpty) {
      final had = sharing.isNotEmpty;
      sharing.clear();
      liveOperators.clear();
      return had;
    }
    final next = <String, Place>{};
    final ops = <String>{};
    await Future.wait(_active.where((s) => !_dead.contains(s.name)).map((s) async {
      try {
        final got = await _loadSystem(s);
        next.addAll(got);
        if (got.isNotEmpty) ops.add(s.operator.toLowerCase());
      } catch (err) {
        // blocked in the browser (no CORS) or offline: do not ask again every 90 s this session
        _dead.add(s.name);
        debugPrint('GBFS ${s.name} failed: $err');
      }
    }));
    // free-floating vehicles: only the nearest few hundred
    final floating = next.entries.where((e) => e.key.startsWith('veh/')).toList();
    if (floating.length > _maxFloating) {
      floating.sort((a, b) => _meters(a.value).compareTo(_meters(b.value)));
      for (final e in floating.skip(_maxFloating)) {
        next.remove(e.key);
      }
    }
    sharing
      ..clear()
      ..addAll(next);
    liveOperators
      ..clear()
      ..addAll(ops);
    return true;
  }

  static double _meters(Place p) => const Distance()(userPos, p.pos);

  Future<Map<String, Place>> _loadSystem(ShareSystem s) async {
    var f = _feeds[s.url];
    if (f == null) {
      final r = await http.get(Uri.parse(s.url)).timeout(const Duration(seconds: 15));
      final data = jsonDecode(r.body)['data'] as Map<String, dynamic>;
      // GBFS 1–2: data.en.feeds ; GBFS 3: data.feeds
      final feedsList = (data['feeds'] ?? (data['en'] ?? data.values.first)['feeds']) as List;
      String? url(String name) => feedsList
          .cast<Map<String, dynamic>>()
          .where((x) => x['name'] == name)
          .map((x) => x['url'] as String)
          .firstOrNull;
      f = (url('station_information'), url('station_status'), url('vehicle_status') ?? url('free_bike_status'));
      _feeds[s.url] = f;
    }
    final (infoUrl, statusUrl, vehUrl) = f;
    final out = <String, Place>{};
    final op = s.operator;
    const d = Distance();

    if (infoUrl != null && statusUrl != null) {
      final res = await Future.wait([
        http.get(Uri.parse(infoUrl)).timeout(const Duration(seconds: 20)),
        http.get(Uri.parse(statusUrl)).timeout(const Duration(seconds: 20)),
      ]);
      final info = (jsonDecode(utf8.decode(res[0].bodyBytes))['data']['stations'] as List).cast<Map<String, dynamic>>();
      final status = {
        for (final x in (jsonDecode(utf8.decode(res[1].bodyBytes))['data']['stations'] as List).cast<Map<String, dynamic>>())
          '${x['station_id']}': x,
      };
      for (final st in info) {
        final id = '${st['station_id']}';
        final lat = (st['lat'] as num?)?.toDouble(), lon = (st['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final x = status[id];
        final bikes = ((x?['num_bikes_available'] ?? x?['num_vehicles_available']) as num?)?.toInt() ?? 0;
        final ebikes = (x?['num_ebikes_available'] as num?)?.toInt() ?? 0;
        final docks = (x?['num_docks_available'] as num?)?.toInt();
        final renting = x == null || x['is_renting'] == null || x['is_renting'] == 1 || x['is_renting'] == true;
        final pos = LatLng(lat, lon);
        final m = d(userPos, pos);
        final accepts = ebikes > 0 ? const [Vehicle.bike, Vehicle.ebike] : const [Vehicle.bike];
        out['sta/${s.url}/$id'] = Place(
          id: 'gbfs/${s.name}/$id',
          type: PlaceType.sharing,
          address: _text(st['name']) ?? '$op station',
          pos: pos,
          status: !renting || bikes == 0 ? Status.full : (bikes <= 2 ? Status.almost : Status.free),
          count: '$bikes',
          age: _age(x?['last_reported']),
          accepts: accepts,
          distance: _fmt(m),
          etaMin: {for (final v in accepts) v: etaMinutes(m, v)},
          operatorName: op,
          osm: true,
          facts: [
            '$bikes available now',
            if (ebikes > 0) '$ebikes e-bikes',
            if (docks != null) '$docks free docks',
            if (st['capacity'] != null) 'Capacity ${st['capacity']}',
            'Live · ${s.name}',
          ],
        );
      }
    }

    if (vehUrl != null) {
      final r = await http.get(Uri.parse(vehUrl)).timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(r.bodyBytes))['data'] as Map<String, dynamic>;
      final list = ((data['vehicles'] ?? data['bikes']) as List? ?? []).cast<Map<String, dynamic>>();
      for (final v in list) {
        final lat = (v['lat'] as num?)?.toDouble(), lon = (v['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue; // docked vehicles have no position of their own
        if (v['is_disabled'] == true || v['is_disabled'] == 1 || v['is_reserved'] == true || v['is_reserved'] == 1) continue;
        final type = '${v['vehicle_type_id'] ?? ''}'.toLowerCase();
        final scooter = type.contains('scooter') || op == 'Bird' || (op == 'Lime' && !type.contains('bike'));
        final vehicle = scooter ? Vehicle.scooter : Vehicle.ebike;
        final pos = LatLng(lat, lon);
        final m = d(userPos, pos);
        final batt = (v['current_fuel_percent'] as num?)?.toDouble();
        out['veh/${s.url}/${v['vehicle_id'] ?? v['bike_id']}'] = Place(
          id: 'gbfs/${s.name}/${v['vehicle_id'] ?? v['bike_id']}',
          type: PlaceType.sharing,
          address: '$op ${scooter ? 'scooter' : 'e-bike'}',
          pos: pos,
          status: Status.free,
          count: '1',
          age: '<1 min',
          accepts: [vehicle],
          distance: _fmt(m),
          etaMin: {vehicle: etaMinutes(m, vehicle)},
          operatorName: op,
          osm: true,
          facts: [
            if (batt != null) 'Battery ${(batt <= 1 ? batt * 100 : batt).round()}%',
            'Live · ${s.name}',
          ],
        );
      }
    }
    return out;
  }

  static String? _text(dynamic n) {
    if (n is String) return n;
    if (n is List && n.isNotEmpty) {
      final en = n.cast<Map>().where((x) => '${x['language']}'.startsWith('en')).firstOrNull ?? n.first as Map;
      return '${en['text']}';
    }
    return null;
  }

  static String _fmt(double m) => m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km';

  static String _age(dynamic reported) {
    int? sec;
    if (reported is num) sec = reported.toInt();
    if (reported is String) sec = (DateTime.tryParse(reported)?.millisecondsSinceEpoch ?? 0) ~/ 1000;
    if (sec == null || sec == 0) return '<5 min';
    final m = math.max(0, DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sec * 1000)).inMinutes);
    if (m < 5) return '<5 min';
    if (m < 15) return '<15 min';
    if (m < 60) return '<1 h';
    return '${m ~/ 60} h';
  }
}
