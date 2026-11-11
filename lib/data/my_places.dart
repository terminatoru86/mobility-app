import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A place the rider keeps: Home, Work, a favourite, or one searched lately.
class KeptPlace {
  final String title, subtitle;
  final LatLng pos;
  const KeptPlace(this.title, this.subtitle, this.pos);

  Map<String, dynamic> toJson() => {'t': title, 's': subtitle, 'la': pos.latitude, 'lo': pos.longitude};
  static KeptPlace fromJson(Map<String, dynamic> j) =>
      KeptPlace('${j['t']}', '${j['s'] ?? ''}', LatLng((j['la'] as num).toDouble(), (j['lo'] as num).toDouble()));

  bool same(KeptPlace o) => const Distance()(pos, o.pos) < 15;
}

/// Home, Work, favourites and recent places for the search panel. Kept on the phone.
class MyPlaces extends ChangeNotifier {
  MyPlaces._();
  static final MyPlaces i = MyPlaces._();
  static const _key = 'my_places_v1';

  KeptPlace? home, work;
  final List<KeptPlace> favourites = [], recent = [];
  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final raw = _p!.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      KeptPlace? one(String k) => j[k] == null ? null : KeptPlace.fromJson(j[k] as Map<String, dynamic>);
      List<KeptPlace> many(String k) =>
          [for (final e in (j[k] as List? ?? const [])) KeptPlace.fromJson(e as Map<String, dynamic>)];
      home = one('home');
      work = one('work');
      favourites
        ..clear()
        ..addAll(many('fav'));
      recent
        ..clear()
        ..addAll(many('recent'));
      notifyListeners();
    } catch (_) {}
  }

  void _save() {
    _p?.setString(
        _key,
        jsonEncode({
          'home': home?.toJson(),
          'work': work?.toJson(),
          'fav': [for (final f in favourites) f.toJson()],
          'recent': [for (final r in recent) r.toJson()],
        }));
    notifyListeners();
  }

  void setHome(KeptPlace? p) {
    home = p;
    _save();
  }

  void setWork(KeptPlace? p) {
    work = p;
    _save();
  }

  bool isFavourite(KeptPlace p) => favourites.any(p.same);

  /// adds it to the favourites, or takes it out if it is already there
  void toggleFavourite(KeptPlace p) {
    final n = favourites.length;
    favourites.removeWhere(p.same);
    if (favourites.length == n) favourites.insert(0, p);
    _save();
  }

  /// a place just searched for: first in the recent list (the last 8 are kept)
  void addRecent(KeptPlace p) {
    recent.removeWhere(p.same);
    recent.insert(0, p);
    if (recent.length > 8) recent.removeRange(8, recent.length);
    _save();
  }
}
