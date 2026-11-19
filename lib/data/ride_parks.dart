import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A place to ride for fun: BMX track, pump track, bike park, skatepark (many take bikes and
/// scooters too). Real places from OpenStreetMap, for the BMX page in Community.
class RidePark {
  final String id, name, kind;
  final LatLng pos;

  /// true: bikes are named in the map data; null: a skatepark that does not say (check the sign there)
  final bool? bikes;
  final bool scooters;
  final List<String> facts; // surface, lit, covered, free …
  final String? hours, phone, website, address;
  final List<String> photos;
  int likes = 0, dislikes = 0, vote = 0; // 1 like, -1 dislike (on this phone for now)

  RidePark({
    required this.id,
    required this.name,
    required this.kind,
    required this.pos,
    required this.bikes,
    required this.scooters,
    this.facts = const [],
    this.hours,
    this.phone,
    this.website,
    this.address,
    this.photos = const [],
  });

  /// who it is for, in a few words
  String get forWhom => bikes == true
      ? (scooters ? 'Bikes and scooters' : 'Bikes welcome')
      : (scooters ? 'Scooters welcome · bikes: check the sign' : 'Skatepark · bikes and scooters: check the sign');
}

const _endpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];
const _cacheKey = 'ride_parks_v1';
const _radiusM = 40000; // 25 miles around the rider
const _days = 7;

List<RidePark>? _mem;
LatLng? _memAt;

/// Every BMX track, pump track, bike park and skatepark within 25 miles of [around], nearest first.
/// Kept on the phone for a week; asked again when the rider has moved more than 10 miles.
Future<List<RidePark>> rideParks(LatLng around) async {
  final live = await _liveParks(around);
  final ours = await _ourParks(around);
  return _sorted(_join(live, ours), around);
}

Future<List<RidePark>> _liveParks(LatLng around) async {
  const d = Distance();
  if (_mem != null && _memAt != null && d(_memAt!, around) < 16000) return _sorted(_mem!, around);
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final at = LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt())).inDays;
      if (age < _days && d(at, around) < 16000) {
        _mem = _parse((j['el'] as List).cast<Map<String, dynamic>>());
        _memAt = at;
        return _sorted(_mem!, around);
      }
    }
  } catch (_) {}

  final a = '(around:$_radiusM,${around.latitude.toStringAsFixed(4)},${around.longitude.toStringAsFixed(4)})';
  final query = '[out:json][timeout:45];('
      'nwr["sport"~"(^|;)(bmx|skateboard|scooter)(;|\$)"]$a;'
      'nwr["leisure"~"^(bikepark|skatepark)\$"]$a;'
      'nwr["cycling"="pump_track"]$a;'
      ');out center tags;';
  for (final url in _endpoints) {
    try {
      final r = await http.post(Uri.parse(url), body: {'data': query}).timeout(const Duration(seconds: 50));
      if (r.statusCode != 200) continue;
      final el = ((jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['elements'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _mem = _parse(el);
      _memAt = around;
      try {
        await prefs?.setString(
            _cacheKey,
            jsonEncode({
              'lat': around.latitude,
              'lon': around.longitude,
              't': DateTime.now().millisecondsSinceEpoch,
              'el': [
                for (final e in el)
                  {'type': e['type'], 'id': e['id'], 'lat': e['lat'], 'lon': e['lon'], 'center': e['center'], 'tags': e['tags']},
              ],
            }));
      } catch (_) {}
      return _sorted(_mem!, around);
    } catch (e) {
      debugPrint('Ride parks failed on $url: $e');
    }
  }
  return _sorted(_mem ?? const [], around);
}

List<RidePark> _sorted(List<RidePark> l, LatLng at) {
  const d = Distance();
  return [...l]..sort((a, b) => d(at, a.pos).compareTo(d(at, b.pos)));
}

List<RidePark> _parse(List<Map<String, dynamic>> el) {
  final out = <RidePark>[];
  for (final e in el) {
    final t = Map<String, dynamic>.from(e['tags'] as Map? ?? const {});
    String? tag(String k) => t[k]?.toString();
    final lat = ((e['lat'] ?? (e['center'] as Map?)?['lat']) as num?)?.toDouble();
    final lon = ((e['lon'] ?? (e['center'] as Map?)?['lon']) as num?)?.toDouble();
    if (lat == null || lon == null) continue;
    // shops and clubs that only carry the sport tag are not places to ride
    if (t.containsKey('shop') || t.containsKey('office') || t.containsKey('club')) continue;
    if (const ['private', 'no'].contains(tag('access'))) continue;
    if (tag('bicycle') == 'no' && !(tag('sport') ?? '').contains('scooter')) continue;

    final sport = (tag('sport') ?? '').split(';').map((s) => s.trim()).toSet();
    final pump = tag('cycling') == 'pump_track';
    final bikePark = tag('leisure') == 'bikepark';
    final bmx = sport.contains('bmx');
    final kind = pump
        ? 'Pump track'
        : bikePark
            ? 'Bike park'
            : bmx
                ? (tag('leisure') == 'track' ? 'BMX track' : 'BMX park')
                : (sport.contains('scooter') && !sport.contains('skateboard') ? 'Scooter park' : 'Skatepark');
    final bikes = (pump || bikePark || bmx || tag('bicycle') == 'yes' || tag('bmx') == 'yes') ? true : null;
    final scooters = sport.contains('scooter') || tag('scooter') == 'yes' || tag('kick_scooter') == 'yes';
    final street = [tag('addr:housenumber'), tag('addr:street')].whereType<String>().join(' ');
    out.add(RidePark(
      id: '${e['type']}/${e['id']}',
      name: tag('name') ?? kind,
      kind: kind,
      pos: LatLng(lat, lon),
      bikes: bikes,
      scooters: scooters,
      facts: [
        if (tag('indoor') == 'yes' || tag('covered') == 'yes') 'Covered',
        if (tag('lit') == 'yes') 'Lit at night',
        if (tag('surface') != null) tag('surface')!.replaceAll('_', ' '),
        if (tag('fee') == 'no') 'Free',
        if (tag('fee') == 'yes') 'Paid',
        if (tag('wheelchair') == 'yes') 'Step-free',
      ],
      hours: tag('opening_hours'),
      phone: tag('phone') ?? tag('contact:phone'),
      website: tag('website') ?? tag('contact:website'),
      address: street.isEmpty ? null : street,
      photos: [
        for (final k in const ['image', 'image:0'])
          if ((tag(k) ?? '').startsWith('http') && RegExp(r'\.(jpe?g|png|webp)(\?|$)', caseSensitive: false).hasMatch(tag(k)!))
            tag(k)!,
      ],
    ));
  }
  return out;
}


// ── our list (tool/ride_parks.py): dirt jumps, pump tracks, bike parks, BMX tracks, also the ones run by a
// business or a club (with their phone, website and hours), from OpenStreetMap, Overture and Foursquare ──
List<List>? _ourAll;

Future<List<RidePark>> _ourParks(LatLng around) async {
  try {
    if (_ourAll == null) {
      final b = await rootBundle.load('assets/ride/ride_parks.json.gz');
      final bytes = Uint8List.view(b.buffer, b.offsetInBytes, b.lengthInBytes);
      _ourAll = (jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes))) as List).cast<List>();
    }
  } catch (e) {
    debugPrint('Our ride parks: $e');
    _ourAll = const [];
  }
  const d = Distance();
  final out = <RidePark>[];
  for (final r in _ourAll!) {
    final pos = LatLng((r[1] as num).toDouble(), (r[2] as num).toDouble());
    if (d(around, pos) > _radiusM) continue;
    final t = Map<String, dynamic>.from(r[3] as Map);
    String? tag(String k) => t[k]?.toString();
    final kind = tag('ride') ?? 'Bike park';
    out.add(RidePark(
      id: '${r[0]}',
      name: tag('name') ?? kind,
      kind: kind,
      pos: pos,
      // a skatepark that does not say: null (the card says "check the sign")
      bikes: tag('bikes') == 'yes' || kind != 'Skatepark' ? true : null,
      scooters: tag('scooters') == 'yes',
      facts: [
        if (tag('in_park') != null) 'In ${tag('in_park')}',
        if (tag('operator') != null) 'Run by ${tag('operator')}',
        if (tag('lit') == 'yes') 'Lit at night',
        if (tag('surface') != null) tag('surface')!.replaceAll('_', ' '),
        if (tag('fee') == 'no') 'Free',
        if (tag('fee') == 'yes') 'Paid',
      ],
      hours: tag('hours'),
      phone: tag('phone'),
      website: tag('website'),
      address: tag('street'),
    ));
  }
  return out;
}

/// The same place from the live map and from our list: kept once (our list fills the phone, website, hours).
List<RidePark> _join(List<RidePark> live, List<RidePark> ours) {
  const d = Distance();
  Set<String> w(String n) =>
      RegExp(r'[a-z0-9]{3,}').allMatches(n.toLowerCase()).map((m) => m[0]!).toSet()..removeAll(const {'the', 'park', 'bike', 'track', 'and'});
  final out = [...live];
  for (final o in ours) {
    final i = out.indexWhere((l) =>
        l.id == o.id ||
        (d(l.pos, o.pos) < 250 && (l.name == l.kind || o.name == o.kind || w(l.name).intersection(w(o.name)).isNotEmpty)));
    if (i < 0) {
      out.add(o);
      continue;
    }
    final l = out[i];
    out[i] = RidePark(
      id: l.id,
      name: l.name == l.kind ? o.name : l.name,
      kind: l.kind == 'Skatepark' ? o.kind : l.kind,
      pos: l.pos,
      bikes: l.bikes ?? o.bikes,
      scooters: l.scooters || o.scooters,
      facts: {...l.facts, ...o.facts}.toList(),
      hours: l.hours ?? o.hours,
      phone: l.phone ?? o.phone,
      website: l.website ?? o.website,
      address: l.address ?? o.address,
      photos: l.photos,
    );
  }
  return out;
}
