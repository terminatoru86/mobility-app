import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mapillary.dart';
import 'places.dart';

/// A photo of a place and where it comes from (shown on the photo).
class PlacePhoto {
  final String url; // http(s) address, or a file on the phone
  final String credit;
  const PlacePhoto(this.url, this.credit);
  bool get local => !url.startsWith('http');
}

final Map<String, Future<List<PlacePhoto>>> _found = {};

/// Open, free photos in which the place itself is in view (not just the street next to it):
///  1. Mapillary photos in which a bike rack was recognised right there (racks and parking);
///  2. Mapillary and Panoramax street photos taken 4–40 m away with the camera turned towards the place;
///  3. photos on Wikimedia Commons taken within 30 m.
/// Shops, service, rent and BMX places change often: for them only photos from 2024 on.
/// For every kind the newer photo wins. Faces and number plates in street photos are blurred by
/// their source. Empty when nothing looks at the place.
Future<List<PlacePhoto>> photosLookingAt(Place p) => _found[p.id] ??= _look(p);

const _d = Distance();

/// Kinds of place whose look changes often: only photos from 2024 on.
bool _wantsRecent(PlaceType t) =>
    t == PlaceType.shop || t == PlaceType.service || t == PlaceType.rent || t == PlaceType.bmx;

final _y2024 = DateTime.utc(2024);

Future<List<PlacePhoto>> _look(Place p) async {
  final out = <PlacePhoto>[];
  try {
    final rackish = p.type.group == 'Parking';
    final since = _wantsRecent(p.type) ? _y2024 : null;
    final res = await Future.wait([
      _near(p.pos, since),
      rackish ? _rackImages(p.pos) : Future.value(const <String>{}),
      _commons(p.pos, since),
      _panoramax(p.pos, since),
    ]);
    var imgs = res[0] as List<Map<String, dynamic>>;
    final rackIds = res[1] as Set<String>;
    final missing = rackIds.difference({for (final e in imgs) '${e['id']}'});
    if (missing.isNotEmpty) imgs = [...imgs, ...await _byIds(missing.take(12))];

    // every street photo as: where the camera stood, where it looked, when, the picture
    final shots = <(LatLng, double, DateTime?, String, String, bool)>[
      ...res[3] as List<(LatLng, double, DateTime?, String, String, bool)>,
    ];
    for (final e in imgs) {
      final url = e['thumb_1024_url'];
      final g = (e['computed_geometry'] as Map?)?['coordinates'] as List?;
      final head = ((e['computed_compass_angle'] ?? e['compass_angle']) as num?)?.toDouble();
      if (url == null || g == null || g.length < 2 || head == null) continue;
      if (e['is_pano'] == true) continue; // a flattened 360° picture shows the place bent
      final at = e['captured_at'] is num ? DateTime.fromMillisecondsSinceEpoch((e['captured_at'] as num).toInt(), isUtc: true) : null;
      shots.add((LatLng((g[1] as num).toDouble(), (g[0] as num).toDouble()), head, at, '$url', 'Mapillary',
          rackIds.contains('${e['id']}')));
    }

    final now = DateTime.now().toUtc();
    final scored = <(double, LatLng, String, String)>[];
    for (final (cam, head, at, url, credit, rack) in shots) {
      if (since != null && (at == null || at.isBefore(since))) continue;
      final m = _d(cam, p.pos);
      // how far the camera is turned away from the place
      var off = ((_d.bearing(cam, p.pos) - head) % 360).abs();
      if (off > 180) off = 360 - off;
      if (m < 4 || m > (rack ? 45 : 40) || off > (rack ? 45 : 30)) continue;
      // best: looking straight at it from about 12 m; a recognised rack counts for a lot; newer wins
      final years = at == null ? 6.0 : now.difference(at).inDays / 365;
      scored.add((off + (m - 12).abs() * 1.2 - (rack ? 25 : 0) + years * 4, cam, url, credit));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    final kept = <LatLng>[];
    for (final s in scored) {
      if (kept.length >= 3) break;
      if (kept.any((k) => _d(k, s.$2) < 5)) continue; // not the same view twice
      kept.add(s.$2);
      out.add(PlacePhoto(s.$3, s.$4));
    }
    out.addAll(res[2] as List<PlacePhoto>);
  } catch (e) {
    debugPrint('Place photos failed: $e');
  }
  return out;
}

String _bbox(LatLng p, double meters) {
  final dLat = meters / 111200, dLng = dLat / 0.75;
  return '${p.longitude - dLng},${p.latitude - dLat},${p.longitude + dLng},${p.latitude + dLat}';
}

const _fields = 'id,thumb_1024_url,computed_geometry,computed_compass_angle,compass_angle,is_pano,captured_at';

Future<List<Map<String, dynamic>>> _get(Map<String, String> q, String path) async {
  final r = await http
      .get(Uri.https('graph.mapillary.com', path, {'access_token': kMapillaryToken, ...q}))
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) return const [];
  return ((jsonDecode(r.body) as Map<String, dynamic>)['data'] as List? ?? []).cast<Map<String, dynamic>>();
}

Future<List<Map<String, dynamic>>> _near(LatLng p, DateTime? since) async {
  try {
    return await _get({
      'fields': _fields,
      'bbox': _bbox(p, 45),
      'limit': '80',
      if (since != null) 'start_captured_at': since.toIso8601String(),
    }, '/images');
  } catch (_) {
    return const [];
  }
}

Future<List<Map<String, dynamic>>> _byIds(Iterable<String> ids) async {
  try {
    return await _get({'fields': _fields, 'image_ids': ids.join(',')}, '/images');
  } catch (_) {
    return const [];
  }
}

/// Ids of the photos in which Mapillary recognised a bike rack within ~25 m.
Future<Set<String>> _rackImages(LatLng p) async {
  try {
    final feats = await _get(
        {'fields': 'id,geometry,images', 'object_values': 'object--bike-rack', 'bbox': _bbox(p, 25), 'limit': '10'},
        '/map_features');
    final ids = <String>{};
    for (final f in feats) {
      final im = f['images'];
      final list = im is Map ? im['data'] as List? : (im is List ? im : null);
      for (final e in list ?? const []) {
        ids.add(e is Map ? '${e['id']}' : '$e');
      }
    }
    return ids;
  } catch (_) {
    return const {};
  }
}

/// Photos on Wikimedia Commons taken within 30 m (free licences; the author is on the photo's page).
/// With [since]: only photos taken (or, when the date is missing, uploaded) from then on. Newest first.
Future<List<PlacePhoto>> _commons(LatLng p, DateTime? since) async {
  try {
    final r = await http
        .get(Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query',
          'format': 'json',
          'origin': '*',
          'generator': 'geosearch',
          'ggscoord': '${p.latitude}|${p.longitude}',
          'ggsradius': '30',
          'ggsnamespace': '6',
          'ggslimit': '10',
          'prop': 'imageinfo',
          'iiprop': 'url|mime|timestamp|extmetadata',
          'iiextmetadatafilter': 'DateTimeOriginal',
          'iiurlwidth': '800',
        }))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return const [];
    final pages = ((jsonDecode(r.body) as Map<String, dynamic>)['query'] as Map?)?['pages'] as Map? ?? const {};
    final found = <(DateTime, String)>[];
    for (final pg in pages.values) {
      if (pg is! Map || pg['imageinfo'] is! List || (pg['imageinfo'] as List).isEmpty) continue;
      final ii = (pg['imageinfo'] as List).first as Map;
      if ('${ii['mime']}' != 'image/jpeg' || ii['thumburl'] == null) continue;
      final taken = '${((ii['extmetadata'] as Map?)?['DateTimeOriginal'] as Map?)?['value'] ?? ''}';
      final year = RegExp(r'(19|20)\d\d').firstMatch(taken)?.group(0);
      final at = year != null
          ? DateTime.utc(int.parse(year), 12, 31)
          : (DateTime.tryParse('${ii['timestamp'] ?? ''}') ?? DateTime.utc(2000));
      if (since != null && at.isBefore(since)) continue;
      found.add((at, '${ii['thumburl']}'));
    }
    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final f in found.take(2)) PlacePhoto(f.$2, 'Wikimedia Commons')];
  } catch (_) {
    return const [];
  }
}

/// Street photos on Panoramax (the open, free street-photo commons) around the place:
/// where the camera stood, where it looked, when, the picture.
Future<List<(LatLng, double, DateTime?, String, String, bool)>> _panoramax(LatLng p, DateTime? since) async {
  try {
    final r = await http
        .get(Uri.https('api.panoramax.xyz', '/api/search', {'bbox': _bbox(p, 45), 'limit': '40'}))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return const [];
    final feats = ((jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['features'] as List? ?? const []);
    final out = <(LatLng, double, DateTime?, String, String, bool)>[];
    for (final f in feats.whereType<Map>()) {
      final g = (f['geometry'] as Map?)?['coordinates'] as List?;
      final pr = f['properties'] as Map? ?? const {};
      final head = (pr['view:azimuth'] as num?)?.toDouble();
      final fov = (pr['pers:interior_orientation'] as Map?)?['field_of_view'] as num?;
      final assets = f['assets'] as Map? ?? const {};
      final url = ((assets['sd'] ?? assets['thumb']) as Map?)?['href'];
      if (g == null || g.length < 2 || head == null || url == null) continue;
      if (fov != null && fov >= 300) continue; // 360° pictures
      final at = DateTime.tryParse('${pr['datetime'] ?? ''}');
      if (since != null && (at == null || at.isBefore(since))) continue;
      out.add((LatLng((g[1] as num).toDouble(), (g[0] as num).toDouble()), head, at?.toUtc(), '$url', 'Panoramax', false));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Photos riders take of a place, with the phone's camera, right there.
/// Kept on this phone for now (shared with everyone once the server is on).
class MyPhotos extends ChangeNotifier {
  MyPhotos._();
  static final MyPhotos i = MyPhotos._();
  static const _key = 'my_place_photos';

  Map<String, List<String>>? _all; // place id -> files, newest first

  Future<Map<String, List<String>>> _load() async {
    if (_all != null) return _all!;
    final all = <String, List<String>>{};
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => all[k] = (v as List).cast<String>());
      }
    } catch (_) {}
    return _all = all;
  }

  /// the photos of [placeId] that are still on the phone
  Future<List<PlacePhoto>> of(String placeId) async {
    if (kIsWeb) return const [];
    final all = await _load();
    return [
      for (final f in all[placeId] ?? const <String>[])
        if (File(f).existsSync()) PlacePhoto(f, 'yours'),
    ];
  }

  /// Opens the camera; the photo is saved for this place. False when nothing was taken.
  Future<bool> take(String placeId) async {
    if (kIsWeb) return false;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
      if (x == null) return false;
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/place_photos');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(await x.readAsBytes());
      final all = await _load();
      all.putIfAbsent(placeId, () => []).insert(0, file.path);
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(all));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Photo failed: $e');
      return false;
    }
  }
}
