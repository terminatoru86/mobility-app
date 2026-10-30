import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Our own street map, kept on the phone (no internet needed to see the map).
///
/// The first time the app opens after install, as soon as GPS says where the rider is,
/// the map of the whole area around (100 miles) is downloaded once, in 1° x 1° pieces,
/// nearest piece first. After that the map comes from the phone. Once a week the app asks
/// which pieces changed and downloads only those.
///
/// The pieces are made on GitHub from Protomaps (OpenStreetMap data, free to keep offline)
/// and published in our public data repository (terminatoru86/mobility-data, releases "map-<lat>").
class Basemap extends ChangeNotifier {
  Basemap._();
  static final Basemap i = Basemap._();

  static const _releases = 'https://github.com/terminatoru86/mobility-data/releases/download/';
  static const _indexUrl = '${_releases}map-index/map_index.json';
  static const checkEveryDays = 7;
  static const radiusMiles = 100.0;

  final Map<String, PmTilesArchive> _open = {}; // piece "41_-88" -> its map file, opened
  Map<String, String> _have = {}; // piece -> version on the phone
  DateTime? _lastCheck;
  Directory? _dir;
  bool _started = false;
  bool _busy = false;

  /// While pieces download: how many are done of how many (for the small pill on the map).
  (int, int)? progress;

  /// True when the phone has at least one piece: then the map is drawn from the phone.
  bool get ready => _open.isNotEmpty;

  /// The map at [p] is on the phone (else the online map is shown there).
  bool covers(LatLng p) => _open.containsKey('${p.latitude.floor()}_${p.longitude.floor()}');

  late final VectorTileProvider provider = _PiecesProvider(this);

  /// Opens the pieces already on the phone (instant, no internet).
  Future<void> start() async {
    if (_started || kIsWeb) return;
    _started = true;
    try {
      _dir = Directory('${(await getApplicationSupportDirectory()).path}/basemap');
      await _dir!.create(recursive: true);
      final meta = File('${_dir!.path}/meta.json');
      if (await meta.exists()) {
        final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        _have = ((j['pieces'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
        final lc = j['lastCheck'] as int?;
        if (lc != null) _lastCheck = DateTime.fromMillisecondsSinceEpoch(lc);
      }
      for (final k in _have.keys.toList()) {
        final f = File(_path(k));
        if (!await f.exists()) {
          _have.remove(k);
          continue;
        }
        try {
          _open[k] = await PmTilesArchive.from(f.path);
        } catch (e) {
          debugPrint('Basemap $k broken: $e');
          _have.remove(k);
        }
      }
      if (_open.isNotEmpty) notifyListeners();
    } catch (e) {
      debugPrint('Basemap start failed: $e');
    }
  }

  String _path(String k) => '${_dir!.path}/m_$k.pmtiles';

  /// The area around [c] (100 miles): downloads what is missing, and once a week what changed.
  final List<LatLng> _next = []; // other areas of the rider, done one after the other
  Future<void> ensure(LatLng c) async {
    if (kIsWeb) return;
    if (_busy) {
      _next.add(c);
      return;
    }
    await start();
    if (_dir == null) return;
    final pieces = _piecesAround(c);
    final missing = pieces.where((k) => !_have.containsKey(k)).toList();
    final due = _lastCheck == null || DateTime.now().difference(_lastCheck!).inDays >= checkEveryDays;
    if (missing.isEmpty && !due) return;
    _busy = true;
    try {
      final r = await http.get(Uri.parse(_indexUrl)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return; // no internet / not published yet: the online map is used
      final idx = jsonDecode(r.body) as Map<String, dynamic>;
      final remote = ((idx['pieces'] as Map?) ?? {}).cast<String, dynamic>();
      final todo = [
        for (final k in pieces)
          if (remote[k] != null && '${(remote[k] as List)[1]}' != _have[k]) k,
      ];
      var done = 0;
      progress = todo.isEmpty ? null : (0, todo.length);
      notifyListeners();
      for (final k in todo) {
        final v = remote[k] as List;
        if (await _download(k, '${idx['release_prefix'] ?? 'map-'}${k.split('_').first}', '${v[1]}')) {
          notifyListeners(); // the map redraws with the new piece
        }
        progress = (++done, todo.length);
        notifyListeners();
      }
      _lastCheck = DateTime.now();
      await _saveMeta();
    } catch (e) {
      debugPrint('Basemap update failed: $e');
    } finally {
      _busy = false;
      progress = null;
      notifyListeners();
    }
    if (_next.isNotEmpty) ensure(_next.removeAt(0));
  }

  Future<bool> _download(String k, String release, String version) async {
    final part = File('${_path(k)}.part');
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse('$_releases$release/m_$k.pmtiles')))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      final sink = part.openWrite();
      await res.stream.timeout(const Duration(seconds: 60)).pipe(sink);
      final old = _open.remove(k);
      final f = await part.rename(_path(k));
      try {
        await (old as dynamic)?.close();
      } catch (_) {}
      _open[k] = await PmTilesArchive.from(f.path);
      _have[k] = version;
      await _saveMeta();
      debugPrint('Basemap piece $k ready');
      return true;
    } catch (e) {
      debugPrint('Basemap piece $k failed: $e');
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _saveMeta() async {
    try {
      await File('${_dir!.path}/meta.json').writeAsString(
          jsonEncode({'lastCheck': _lastCheck?.millisecondsSinceEpoch, 'pieces': _have}));
    } catch (_) {}
  }

  /// The 1° pieces within 100 miles of [c], nearest first.
  static List<String> _piecesAround(LatLng c) {
    final rLat = radiusMiles * 1.609 / 111.2;
    final rLng = rLat / math.max(0.2, math.cos(c.latitude * math.pi / 180));
    final list = <(String, double)>[];
    for (int a = (c.latitude - rLat).floor(); a <= (c.latitude + rLat).floor(); a++) {
      for (int b = (c.longitude - rLng).floor(); b <= (c.longitude + rLng).floor(); b++) {
        final dy = (a + 0.5 - c.latitude), dx = (b + 0.5 - c.longitude) * math.cos(c.latitude * math.pi / 180);
        list.add(('${a}_$b', dx * dx + dy * dy));
      }
    }
    list.sort((x, y) => x.$2.compareTo(y.$2));
    return [for (final e in list) e.$1];
  }
}

/// Gives the map each square from the piece on the phone that has it.
class _PiecesProvider extends VectorTileProvider {
  _PiecesProvider(this.b);
  final Basemap b;

  @override
  int get maximumZoom => 14; // more detail is drawn from zoom 14 (vector map: stays sharp)

  @override
  int get minimumZoom => 0;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(TileIdentity t) async {
    final n = math.pow(2, t.z).toDouble();
    double lon(num x) => x / n * 360 - 180;
    double lat(num y) {
      final r = math.pi * (1 - 2 * y / n);
      return 180 / math.pi * math.atan((math.exp(r) - math.exp(-r)) / 2);
    }

    final w = lon(t.x), e = lon(t.x + 1), north = lat(t.y), s = lat(t.y + 1);
    final cLat = (s + north) / 2, cLng = (w + e) / 2;
    // pieces touching this square, the one under its middle first
    final keys = b._open.keys.where((k) {
      final p = k.split('_');
      final a = int.parse(p[0]), c = int.parse(p[1]);
      return a < north && a + 1 > s && c < e && c + 1 > w;
    }).toList()
      ..sort((x, y) {
        double d(String k) {
          final p = k.split('_');
          final dy = int.parse(p[0]) + 0.5 - cLat, dx = int.parse(p[1]) + 0.5 - cLng;
          return dx * dx + dy * dy;
        }

        return d(x).compareTo(d(y));
      });
    final id = ZXY(t.z, t.x, t.y).toTileId();
    for (final k in keys) {
      final arch = b._open[k];
      if (arch == null) continue;
      try {
        final tile = await arch.tile(id);
        return Uint8List.fromList(tile.bytes());
      } on TileNotFoundException {
        // not in this piece: try the next one
      } catch (_) {}
    }
    throw ProviderException(message: 'No map here yet: $t', retryable: Retryable.none, statusCode: 404);
  }
}
