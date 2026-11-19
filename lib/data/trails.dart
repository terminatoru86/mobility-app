import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real bike / mountain-bike / motorcycle route (manual 4.1, Explore), from parks, forests, cities
/// and OpenStreetMap. Built by tool/trails_tiles.py into 1° pieces that the app downloads by area.
class Trail {
  final String id, name, kind; // kind: bicycle / mtb / motorcycle
  final double km;
  final String? operator, from, to, website;
  final List<List<LatLng>> lines; // in riding order
  /// What riders see along the way, in line order: (km from the start, 'L' / 'R' / 'on', name, kind).
  final List<(double, String, String, String)> sights;

  Trail(this.id, this.name, this.kind, this.km, this.operator, this.from, this.to, this.website, this.lines,
      [this.sights = const []]);

  factory Trail.fromRow(List r) {
    final lines = <List<LatLng>>[
      for (final s in (r[8] as List))
        [for (int i = 0; i + 1 < (s as List).length; i += 2) LatLng((s[i] as num).toDouble(), (s[i + 1] as num).toDouble())],
    ].where((l) => l.length > 1).toList();
    final sights = <(double, String, String, String)>[
      if (r.length > 9 && r[9] is List)
        for (final x in (r[9] as List))
          if (x is List && x.length >= 4) ((x[0] as num).toDouble(), '${x[1]}', '${x[2]}', '${x[3]}'),
    ];
    return Trail('${r[0]}', '${r[1]}', '${r[2]}', (r[3] as num?)?.toDouble() ?? 0, r[4] as String?, r[5] as String?,
        r[6] as String?, r[7] as String?, lines, sights);
  }

  LatLng get start => lines.first.first;
  LatLng get end => lines.last.last;
  List<LatLng> get points => [for (final l in lines) ...l];

  double get miles => km / 1.609344;

  /// Bike ~15 km/h, MTB ~12 km/h, motorcycle ~50 km/h on these roads.
  double get minutes => km / (kind == 'mtb' ? 12 : kind == 'motorcycle' ? 50 : 15) * 60;

  String get kindLabel => switch (kind) { 'mtb' => 'MTB', 'motorcycle' => 'Moto', _ => 'Bike' };

  String get milesText => '${miles.toStringAsFixed(1)} mi';

  String get timeText {
    final m = (minutes / 5).round() * 5;
    if (m < 60) return '~${math.max(5, m)} min';
    return m % 60 == 0 ? '~${m ~/ 60} h' : '~${m ~/ 60} h ${m % 60}';
  }

  String? get fromTo => (from != null && to != null) ? '$from → $to' : null;

  /// The nearest end of the route (where the rider can start it).
  double metersFrom(LatLng p) {
    const d = Distance();
    return math.min(d(p, start), d(p, end));
  }
}

/// Downloads the route pieces around the rider and keeps them on the phone (a month).
class Trails {
  Trails._();
  static final Trails i = Trails._();

  static const site = 'https://raw.githubusercontent.com/terminatoru86/mobility-app/master/data/trails/tiles/';
  static const keepDays = 30;

  Map<String, int>? _index; // piece -> number of routes
  final Map<String, List<Trail>> _mem = {};
  Directory? _dir;

  Future<void> _open() async {
    if (_dir != null || kIsWeb) return;
    _dir = Directory('${(await getApplicationSupportDirectory()).path}/trails');
    await _dir!.create(recursive: true);
  }

  Future<String?> _cached(String name) async {
    try {
      if (kIsWeb) return (await SharedPreferences.getInstance()).getString('trails_$name');
      await _open();
      final f = File('${_dir!.path}/$name');
      if (!await f.exists()) return null;
      if (DateTime.now().difference(await f.lastModified()).inDays >= keepDays) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _keep(String name, String body) async {
    try {
      if (kIsWeb) {
        await (await SharedPreferences.getInstance()).setString('trails_$name', body);
        return;
      }
      await _open();
      await File('${_dir!.path}/$name').writeAsString(body);
    } catch (e) {
      debugPrint('Trails keep $name failed: $e');
    }
  }

  Future<Map<String, int>> _loadIndex() async {
    if (_index != null) return _index!;
    var raw = await _cached('index.json');
    if (raw == null) {
      try {
        final r = await http.get(Uri.parse('${site}index.json')).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          raw = r.body;
          await _keep('index.json', raw);
        }
      } catch (e) {
        debugPrint('Trails index failed: $e');
      }
    }
    if (raw == null) return const {};
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return _index = ((j['tiles'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt()));
  }

  Future<List<Trail>> _tile(String key) async {
    final have = _mem[key];
    if (have != null) return have;
    var raw = await _cached('t_$key.json');
    if (raw == null) {
      try {
        final r = await http.get(Uri.parse('${site}t_$key.json.gz')).timeout(const Duration(seconds: 40));
        if (r.statusCode != 200) return const [];
        raw = utf8.decode(GZipDecoder().decodeBytes(r.bodyBytes));
        await _keep('t_$key.json', raw);
      } catch (e) {
        debugPrint('Trails piece $key failed: $e');
        return const [];
      }
    }
    try {
      final l = [for (final r in jsonDecode(raw) as List) Trail.fromRow(r as List)]..removeWhere((t) => t.lines.isEmpty);
      return _mem[key] = l;
    } catch (e) {
      debugPrint('Trails piece $key unreadable: $e');
      return const [];
    }
  }

  /// Routes that start within [miles] of [at], nearest first.
  Future<List<Trail>> near(LatLng at, {double miles = 40}) async {
    final idx = await _loadIndex();
    final m = miles * 1609.344;
    final dLat = (m / 111000).ceil();
    final dLon = (m / (111000 * math.cos(at.latitude * math.pi / 180))).ceil();
    final la = at.latitude.floor(), lo = at.longitude.floor();
    final keys = [
      for (int i = la - dLat; i <= la + dLat; i++)
        for (int j = lo - dLon; j <= lo + dLon; j++)
          if (idx.isEmpty || idx.containsKey('${i}_$j')) '${i}_$j',
    ];
    final all = <Trail>[];
    for (final l in await Future.wait(keys.map(_tile))) {
      all.addAll(l);
    }
    final out = [for (final t in all) if (t.metersFrom(at) <= m) t];
    out.sort((a, b) => a.metersFrom(at).compareTo(b.metersFrom(at)));
    return out;
  }
}

/// 10 routes free (the ones the rider picks), then \$1 a route. A route taken once stays the rider's.
/// On this phone for now; the payment is a demo, like the map areas.
class TrailPass {
  TrailPass._();
  static final TrailPass i = TrailPass._();

  static const freeCount = 10;
  static const price = '\$1';

  final Set<String> free = {}, paid = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      free.addAll(p.getStringList('trailsFree') ?? const []);
      paid.addAll(p.getStringList('trailsPaid') ?? const []);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('trailsFree', free.toList());
      await p.setStringList('trailsPaid', paid.toList());
    } catch (_) {}
  }

  int get freeLeft => math.max(0, freeCount - free.length);
  bool owns(String id) => free.contains(id) || paid.contains(id);

  /// Takes one of the free routes. False when none is left.
  Future<bool> takeFree(String id) async {
    if (owns(id)) return true;
    if (freeLeft == 0) return false;
    free.add(id);
    await _save();
    return true;
  }

  Future<void> buy(String id) async {
    paid.add(id);
    await _save();
  }
}
