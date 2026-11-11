import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// What a shop says about itself on its own website: opening hours and phone.
class SiteInfo {
  final String? hours; // like the map data: "Mo-Fr 10:00-18:00; Sa 10:00-17:00"
  final String? phone;
  const SiteInfo({this.hours, this.phone});
  bool get isEmpty => hours == null && phone == null;
}

const _days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
const _names = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

String? _hhmm(Object? v) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${v ?? ''}'.trim());
  return m == null ? null : '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
}

/// schema.org openingHoursSpecification → "Mo-Fr 10:00-18:00; Sa 10:00-17:00"
String? _fromSpec(Object? spec) {
  final byDay = <int, String>{};
  for (final s in spec is List ? spec : [spec]) {
    if (s is! Map) continue;
    final o = _hhmm(s['opens']), c = _hhmm(s['closes']);
    if (o == null || c == null || o == c) continue; // no times, or closed that day
    final d = s['dayOfWeek'];
    for (final x in d is List ? d : [d]) {
      final name = '${x is Map ? x['name'] ?? x['@id'] : x}'.toLowerCase().split('/').last;
      final i = _names.indexOf(name);
      if (i >= 0) byDay[i] = byDay.containsKey(i) ? '${byDay[i]},$o-$c' : '$o-$c';
    }
  }
  if (byDay.isEmpty) return null;
  final parts = <String>[];
  var i = 0;
  while (i < 7) {
    final h = byDay[i];
    if (h == null) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < 7 && byDay[j + 1] == h) {
      j++;
    }
    parts.add('${i == j ? _days[i] : '${_days[i]}-${_days[j]}'} $h');
    i = j + 1;
  }
  return parts.join('; ');
}

void _walk(Object? node, Set<String> hours, Set<String> phones) {
  if (node is List) {
    for (final n in node) {
      _walk(n, hours, phones);
    }
  } else if (node is Map) {
    final spec = _fromSpec(node['openingHoursSpecification']);
    if (spec != null) {
      hours.add(spec);
    } else {
      final oh = node['openingHours'];
      final text = (oh is List ? oh.join('; ') : '${oh ?? ''}').trim();
      if (RegExp(r'\d{1,2}:\d{2}').hasMatch(text) && text.length < 160) hours.add(text);
    }
    final tel = node['telephone'];
    if (tel is String && RegExp(r'\d{3}').hasMatch(tel) && tel.length < 30) phones.add(tel.trim());
    for (final v in node.values) {
      if (v is Map || v is List) _walk(v, hours, phones);
    }
  }
}

/// Reads the hours and phone a web page states about the business, from the structured data
/// (schema.org) shops put in their pages for search engines. Nothing is guessed from the text.
/// Kept only when the page states ONE set of hours: a page listing several stores is left alone.
SiteInfo parseSiteInfo(String html) {
  final hours = <String>{}, phones = <String>{};
  final re = RegExp(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', dotAll: true, caseSensitive: false);
  for (final m in re.allMatches(html)) {
    try {
      _walk(jsonDecode(m.group(1)!.trim()), hours, phones);
    } catch (_) {}
  }
  return SiteInfo(hours: hours.length == 1 ? hours.first : null, phone: phones.length == 1 ? phones.first : null);
}

final _mem = <String, SiteInfo>{};

/// The hours and phone from a place's own website (kept on the phone for two weeks).
Future<SiteInfo> siteInfo(String website) async {
  final url = website.startsWith('http') ? website : 'https://$website';
  final hit = _mem[url];
  if (hit != null) return hit;
  final key = 'site_v1_$url';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(key);
    if (saved != null && saved.length == 3) {
      final at = int.tryParse(saved[0]) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at < 14 * 86400000) {
        return _mem[url] = SiteInfo(hours: saved[1].isEmpty ? null : saved[1], phone: saved[2].isEmpty ? null : saved[2]);
      }
    }
  } catch (_) {}
  var info = const SiteInfo();
  try {
    final r = await http.get(Uri.parse(url), headers: const {'Accept': 'text/html'}).timeout(const Duration(seconds: 8));
    if (r.statusCode == 200 && r.bodyBytes.length < 3000000) {
      info = parseSiteInfo(utf8.decode(r.bodyBytes, allowMalformed: true));
    } else {
      return info; // the site did not answer now: try again next time
    }
  } catch (_) {
    return info;
  }
  _mem[url] = info;
  try {
    await prefs?.setStringList(key, ['${DateTime.now().millisecondsSinceEpoch}', info.hours ?? '', info.phone ?? '']);
  } catch (_) {}
  return info;
}
