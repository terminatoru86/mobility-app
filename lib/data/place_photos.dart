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

/// Open street photos in which the place itself is in view (not just the street next to it):
///  1. Mapillary photos in which a bike rack was recognised right there (racks and parking);
///  2. Mapillary photos taken 4–40 m away with the camera turned towards the place;
///  3. photos on Wikimedia Commons taken within 30 m.
/// Faces and number plates in Mapillary photos are blurred by Mapillary. Empty when nothing looks at the place.
Future<List<PlacePhoto>> photosLookingAt(Place p) => _found[p.id] ??= _look(p);

const _d = Distance();

Future<List<PlacePhoto>> _look(Place p) async {
  final out = <PlacePhoto>[];
  try {
    final rackish = p.type.group == 'Parking';
    final res = await Future.wait([
      _near(p.pos),
      rackish ? _rackImages(p.pos) : Future.value(const <String>{}),
      _commons(p.pos),
    ]);
    var imgs = res[0] as List<Map<String, dynamic>>;
    final rackIds = res[1] as Set<String>;
    final missing = rackIds.difference({for (final e in imgs) '${e['id']}'});
    if (missing.isNotEmpty) imgs = [...imgs, ...await _byIds(missing.take(12))];

    final scored = <(double, LatLng, String)>[];
    for (final e in imgs) {
      final url = e['thumb_1024_url'];
      final g = (e['computed_geometry'] as Map?)?['coordinates'] as List?;
      final head = ((e['computed_compass_angle'] ?? e['compass_angle']) as num?)?.toDouble();
      if (url == null || g == null || g.length < 2 || head == null) continue;
      if (e['is_pano'] == true) continue; // a flattened 360° picture shows the place bent
      final cam = LatLng((g[1] as num).toDouble(), (g[0] as num).toDouble());
      final m = _d(cam, p.pos);
      // how far the camera is turned away from the place
      var off = ((_d.bearing(cam, p.pos) - head) % 360).abs();
      if (off > 180) off = 360 - off;
      final rack = rackIds.contains('${e['id']}');
      if (m < 4 || m > (rack ? 45 : 40) || off > (rack ? 45 : 30)) continue;
      // best: looking straight at it from about 12 m; a recognised rack counts for a lot
      scored.add((off + (m - 12).abs() * 1.2 - (rack ? 25 : 0), cam, '$url'));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    final kept = <LatLng>[];
    for (final s in scored) {
      if (kept.length >= 3) break;
      if (kept.any((k) => _d(k, s.$2) < 5)) continue; // not the same view twice
      kept.add(s.$2);
      out.add(PlacePhoto(s.$3, 'Mapillary'));
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

Future<List<Map<String, dynamic>>> _near(LatLng p) async {
  try {
    return await _get({'fields': _fields, 'bbox': _bbox(p, 45), 'limit': '80'}, '/images');
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
Future<List<PlacePhoto>> _commons(LatLng p) async {
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
          'ggslimit': '6',
          'prop': 'imageinfo',
          'iiprop': 'url|mime',
          'iiurlwidth': '800',
        }))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return const [];
    final pages = ((jsonDecode(r.body) as Map<String, dynamic>)['query'] as Map?)?['pages'] as Map? ?? const {};
    return [
      for (final pg in pages.values)
        if (pg is Map && pg['imageinfo'] is List && (pg['imageinfo'] as List).isNotEmpty)
          if ('${(pg['imageinfo'] as List).first['mime']}' == 'image/jpeg' &&
              (pg['imageinfo'] as List).first['thumburl'] != null)
            PlacePhoto('${(pg['imageinfo'] as List).first['thumburl']}', 'Wikimedia Commons'),
    ].take(2).toList();
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
