import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
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
