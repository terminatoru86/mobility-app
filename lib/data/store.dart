import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places.dart';

/// A saved route ("Home → Office").
class SavedRoute {
  final String name;
  final LatLng from, to;
  final double meters, seconds;
  const SavedRoute(this.name, this.from, this.to, this.meters, this.seconds);

  Map<String, dynamic> toJson() => {
        'n': name,
        'f': [from.latitude, from.longitude],
        't': [to.latitude, to.longitude],
        'm': meters,
        's': seconds,
      };
  static SavedRoute fromJson(Map<String, dynamic> j) => SavedRoute(
        j['n'] as String,
        LatLng((j['f'][0] as num).toDouble(), (j['f'][1] as num).toDouble()),
        LatLng((j['t'][0] as num).toDouble(), (j['t'][1] as num).toDouble()),
        (j['m'] as num).toDouble(),
        (j['s'] as num).toDouble(),
      );
}

/// Something a rider reported with the + button.
class Report {
  final String kind; // New place, Blocked road, Risk zone, ...
  final String detail; // e.g. "Potholes"
  final String text;
  final LatLng pos;
  final DateTime at;
  const Report(this.kind, this.detail, this.text, this.pos, this.at);

  IconData get icon => switch (kind) {
        'Blocked road' => Icons.block,
        'Risk zone' => Icons.warning_amber_rounded,
        'Map correction' => Icons.signpost_outlined,
        'Abandoned vehicle' => Icons.no_transfer,
        'I like this lane' => Icons.favorite,
        'New place' => Icons.add_location_alt_outlined,
        _ => Icons.lightbulb_outline,
      };

  /// Only these appear on the map for everyone.
  bool get onMap => kind == 'Blocked road' || kind == 'Risk zone' || kind == 'I like this lane';
}

/// What riders confirmed in Stats (overrides the shown status).
class Confirmation {
  final Status status;
  final DateTime at;
  const Confirmation(this.status, this.at);
}

class UserReview {
  final String placeId;
  final int stars;
  final String text;
  final DateTime at;
  const UserReview(this.placeId, this.stars, this.text, this.at);
}

/// Everything the rider saves or changes in the app (on this phone for now; Firebase in M2).
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  SharedPreferences? _p;

  final Set<String> savedPlaces = {};
  final Map<String, Place> savedPlaceData = {};
  final List<SavedRoute> savedRoutes = [];
  final List<Report> reports = [];
  final Map<String, Confirmation> confirmations = {};
  final List<UserReview> myReviews = [];
  final Map<String, List<QA>> myQuestions = {};
  final List<String> recentSearches = [];

  bool satellite = false;
  ThemeMode theme = ThemeMode.light;
  final Map<PlaceType, bool> showOnMap = {for (final t in PlaceType.values) t: true};
  final Map<String, bool> notifications = {
    'SOS nearby': true,
    'Theft alert in your area': true,
    'Service reply': true,
    'Rent / sharing booking': true,
    'Ride with Friends': false,
    'Marketplace': false,
    'Rain on a saved route': false,
  };
  final Set<String> operators = {'Divvy', 'Lime'};

  // SOS
  bool sosActive = false;
  String sosText = '';
  bool sosFirstUseShown = false;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final p = _p!;
    savedPlaces.addAll(p.getStringList('savedPlaces') ?? const []);
    for (final s in p.getStringList('savedRoutes') ?? const <String>[]) {
      try {
        savedRoutes.add(SavedRoute.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    recentSearches.addAll(p.getStringList('recent') ?? const []);
    satellite = p.getBool('satellite') ?? false;
    theme = ThemeMode.values[(p.getInt('theme') ?? 1).clamp(0, 2)];
    sosFirstUseShown = p.getBool('sosFirst') ?? false;
    final ops = p.getStringList('operators');
    if (ops != null) {
      operators
        ..clear()
        ..addAll(ops);
    }
  }

  void toggleSaved(Place p) {
    if (savedPlaces.remove(p.id)) {
      savedPlaceData.remove(p.id);
    } else {
      savedPlaces.add(p.id);
      savedPlaceData[p.id] = p;
    }
    _p?.setStringList('savedPlaces', savedPlaces.toList());
    notifyListeners();
  }

  bool isSaved(Place p) => savedPlaces.contains(p.id);

  void saveRoute(SavedRoute r) {
    savedRoutes.insert(0, r);
    _p?.setStringList('savedRoutes', [for (final x in savedRoutes) jsonEncode(x.toJson())]);
    notifyListeners();
  }

  void removeRoute(SavedRoute r) {
    savedRoutes.remove(r);
    _p?.setStringList('savedRoutes', [for (final x in savedRoutes) jsonEncode(x.toJson())]);
    notifyListeners();
  }

  void addReport(Report r) {
    reports.insert(0, r);
    notifyListeners();
  }

  void confirm(String placeId, Status s) {
    confirmations[placeId] = Confirmation(s, DateTime.now());
    notifyListeners();
  }

  void addReview(UserReview r) {
    myReviews.insert(0, r);
    notifyListeners();
  }

  void ask(String placeId, String q) {
    myQuestions.putIfAbsent(placeId, () => []).insert(0, QA(q, 'Waiting for an answer from the community.'));
    notifyListeners();
  }

  void addRecent(String s) {
    recentSearches.remove(s);
    recentSearches.insert(0, s);
    if (recentSearches.length > 6) recentSearches.removeLast();
    _p?.setStringList('recent', recentSearches);
  }

  void setSatellite(bool v) {
    satellite = v;
    _p?.setBool('satellite', v);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    theme = m;
    _p?.setInt('theme', m.index);
    notifyListeners();
  }

  void setShow(PlaceType t, bool v) {
    showOnMap[t] = v;
    notifyListeners();
  }

  void setAllShown(bool v) {
    for (final t in PlaceType.values) {
      showOnMap[t] = v;
    }
    notifyListeners();
  }

  void setNotification(String k, bool v) {
    notifications[k] = v;
    notifyListeners();
  }

  void setOperators(Set<String> ops) {
    operators
      ..clear()
      ..addAll(ops);
    _p?.setStringList('operators', ops.toList());
    notifyListeners();
  }

  void startSos(String text) {
    sosActive = true;
    sosText = text;
    if (!sosFirstUseShown) {
      sosFirstUseShown = true;
      _p?.setBool('sosFirst', true);
    }
    notifyListeners();
  }

  void cancelSos() {
    sosActive = false;
    notifyListeners();
  }

  void changed() => notifyListeners();
}
