// Downloads every rider place in a city from OpenStreetMap into
// assets/osm/<name>.json, so the app shows them instantly, without internet.
//
// Run from the project folder:
//   dart run tool/fetch_osm.dart                 (Chicago)
//   dart run tool/fetch_osm.dart chicago 41.64 -87.94 42.03 -87.52
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const endpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

Future<void> main(List<String> args) async {
  final name = args.isNotEmpty ? args[0] : 'chicago';
  final b = args.length >= 5 ? args.sublist(1, 5) : ['41.64', '-87.94', '42.03', '-87.52'];
  final bbox = b.join(',');
  final query = '[out:json][timeout:180];('
      'nwr["amenity"="bicycle_parking"]($bbox);'
      'nwr["amenity"="bicycle_repair_station"]($bbox);'
      'nwr["amenity"="compressed_air"]($bbox);'
      'nwr["amenity"="bicycle_wash"]($bbox);'
      'nwr["amenity"="bicycle_rental"]($bbox);'
      'nwr["shop"="bicycle"]($bbox);'
      'nwr["amenity"="charging_station"]["bicycle"="yes"]($bbox);'
      ');out center tags;';

  for (final url in endpoints) {
    stdout.writeln('Asking $url ...');
    try {
      final r = await http
          .post(Uri.parse(url), body: {'data': query}, headers: {'User-Agent': 'MOBIlity/0.1 (com.mobility.app)'})
          .timeout(const Duration(minutes: 4));
      if (r.statusCode != 200) {
        stdout.writeln('  server answered ${r.statusCode}: ${r.body.substring(0, r.body.length.clamp(0, 200))}');
        continue;
      }
      final els = (jsonDecode(utf8.decode(r.bodyBytes))['elements'] as List).cast<Map<String, dynamic>>();
      final keep = {
        'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name',
        'brand', 'network', 'operator', 'shop', 'bicycle', 'opening_hours', 'phone', 'contact:phone', 'website',
        'contact:website', 'addr:housenumber', 'addr:street',
      };
      final out = <Map<String, dynamic>>[];
      final count = <String, int>{};
      for (final el in els) {
        final lat = el['lat'] ?? el['center']?['lat'];
        final lon = el['lon'] ?? el['center']?['lon'];
        if (lat == null || lon == null) continue;
        final tags = Map<String, dynamic>.from(el['tags'] as Map? ?? {});
        tags.removeWhere((k, _) => !keep.contains(k) && !k.startsWith('service:bicycle:'));
        out.add({'id': '${el['type']}/${el['id']}', 'lat': lat, 'lon': lon, 'tags': tags});
        final kind = (tags['amenity'] ?? 'shop=${tags['shop']}').toString();
        count[kind] = (count[kind] ?? 0) + 1;
      }
      final file = File('assets/osm/$name.json');
      await file.writeAsString(jsonEncode(out));
      stdout.writeln('Saved ${out.length} places to ${file.path}');
      count.forEach((k, v) => stdout.writeln('  $k: $v'));
      return;
    } catch (e) {
      stdout.writeln('  failed: $e');
    }
  }
  stdout.writeln('All servers failed. Try again in a few minutes.');
  exitCode = 1;
}
