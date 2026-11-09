import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_ledger.dart';
import 'places.dart';
import 'zones.dart';

/// An SOS from another rider, shown as a note on the map.
class IncomingSos {
  final String text;
  final LatLng pos; // approximate area
  final Uint8List? photo;
  final String? photoAsset; // demo photo
  final DateTime at;
  IncomingSos(this.text, this.pos, {this.photo, this.photoAsset, DateTime? at}) : at = at ?? DateTime.now();
}

/// Someone pressed "I can help" on my SOS.
class SosHelper {
  final String name;
  LatLng pos;
  double meters;
  SosHelper(this.name, this.pos, this.meters);
}

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
  final String kind; // New place, Road problem, Map correction, Abandoned vehicle, Feedback
  final String detail; // e.g. "Potholes"
  final String text;
  final LatLng pos;
  final DateTime at;
  const Report(this.kind, this.detail, this.text, this.pos, this.at);

  bool get likesLane => kind == 'I like this lane' || (kind == 'Feedback' && detail.contains('like'));

  IconData get icon => switch (kind) {
        'Road problem' => detail.contains('Construction') || detail.contains('closed') || detail.contains('Accident') || detail.contains('Festival')
            ? Icons.block
            : Icons.warning_amber_rounded,
        'Feedback' => likesLane ? Icons.favorite : Icons.lightbulb_outline,
        'Blocked road' => Icons.block,
        'Risk zone' => Icons.warning_amber_rounded,
        'Map correction' => Icons.signpost_outlined,
        'Abandoned vehicle' => Icons.no_transfer,
        'I like this lane' => Icons.favorite,
        'New place' => Icons.add_location_alt_outlined,
        _ => Icons.lightbulb_outline,
      };

  /// Only these appear on the map for everyone.
  bool get onMap => kind == 'Road problem' || kind == 'Blocked road' || kind == 'Risk zone' || likesLane;
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
  bool bikeMap = false; // CyclOSM: the OpenStreetMap map drawn for cyclists
  bool parkNearDest = true; // after an address search, show the parking around it
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
  Uint8List? sosPhoto;
  IncomingSos? incomingSos;
  SosHelper? sosHelper;
  Timer? _helperTimer;

  // Map areas: 2 free (100 miles each), others unlocked with \$1 for 30 days.
  final List<MapZone> zones = [];
  DateTime? lastMove;

  /// Free areas this PHONE has ever taken (moving one does not count). Kept with the phone's id,
  /// so uninstalling / a new account does not give new free areas.
  int freeEver = 0;
  final Completer<void> _ledgerReady = Completer<void>();
  Future<void> get ledgerReady => _ledgerReady.future;

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
    for (final z in p.getStringList('zones') ?? const <String>[]) {
      try {
        zones.add(MapZone.fromJson(jsonDecode(z) as Map<String, dynamic>));
      } catch (_) {}
    }
    final lm = p.getInt('lastMove');
    if (lm != null) lastMove = DateTime.fromMillisecondsSinceEpoch(lm);
    freeEver = p.getInt('freeEver') ?? zones.where((z) => !z.paid).length;
    _restoreLedger(); // the phone's record (survives a reinstall): checked in the background
    satellite = p.getBool('satellite') ?? false;
    bikeMap = p.getBool('bikeMap') ?? false;
    parkNearDest = p.getBool('parkNearDest') ?? true;
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
    if (v) bikeMap = false;
    _p?.setBool('satellite', v);
    _p?.setBool('bikeMap', bikeMap);
    notifyListeners();
  }

  /// 'Road', 'Bike' (CyclOSM) or 'Satellite'.
  String get mapStyle => satellite ? 'Satellite' : (bikeMap ? 'Bike' : 'Road');

  void setMapStyle(String v) {
    satellite = v == 'Satellite';
    bikeMap = v == 'Bike';
    _p?.setBool('satellite', satellite);
    _p?.setBool('bikeMap', bikeMap);
    notifyListeners();
  }

  /// Two taps on ◎: Road → Bike → Satellite → Road.
  void nextMapStyle() => setMapStyle(switch (mapStyle) { 'Road' => 'Bike', 'Bike' => 'Satellite', _ => 'Road' });

  void setParkNearDest(bool v) {
    parkNearDest = v;
    _p?.setBool('parkNearDest', v);
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

  void startSos(String text, {Uint8List? photo, LatLng? at}) {
    sosActive = true;
    sosText = text;
    sosPhoto = photo;
    if (!sosFirstUseShown) {
      sosFirstUseShown = true;
      _p?.setBool('sosFirst', true);
    }
    notifyListeners();
    if (at != null) _demoHelper(at);
  }

  void cancelSos() {
    sosActive = false;
    sosPhoto = null;
    sosHelper = null;
    _helperTimer?.cancel();
    notifyListeners();
  }

  /// Demo until the server exists: 6 s after the SOS, "Andrei" presses I can help
  /// and comes from 1.2 km away; his green dot moves towards me.
  void _demoHelper(LatLng me) {
    _helperTimer?.cancel();
    final start = LatLng(me.latitude + 0.0085, me.longitude - 0.0075);
    _helperTimer = Timer(const Duration(seconds: 6), () {
      if (!sosActive) return;
      sosHelper = SosHelper('Andrei', start, const Distance()(start, me));
      notifyListeners();
      var k = 0;
      _helperTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!sosActive || sosHelper == null) {
          t.cancel();
          return;
        }
        k++;
        final f = (k / 240).clamp(0.0, 0.97); // about 4 minutes
        final h = sosHelper!;
        h.pos = LatLng(start.latitude + (me.latitude - start.latitude) * f, start.longitude + (me.longitude - start.longitude) * f);
        h.meters = const Distance()(h.pos, me);
        notifyListeners();
      });
    });
  }

  /// Demo: an SOS from a rider about 1.2 km away (Profile → Test).
  void simulateIncomingSos(LatLng me) {
    incomingSos = IncomingSos(
      'My chain broke and I fell. My knee hurts.',
      LatLng(me.latitude - 0.0079, me.longitude + 0.0098),
      photoAsset: 'assets/vehicles/bike.png',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    notifyListeners();
  }

  void dismissIncomingSos() {
    incomingSos = null;
    notifyListeners();
  }

  void changed() => notifyListeners();

  // ───────── map areas ─────────

  List<MapZone> get freeZones => zones.where((z) => !z.paid).toList();
  bool unlockedAt(LatLng p) => zones.any((z) => z.covers(p));
  MapZone? zoneAt(LatLng p) => zones.where((z) => z.covers(p)).firstOrNull;

  void _saveZones({bool sync = true}) {
    zones.removeWhere((z) => z.paid && !z.active && DateTime.now().difference(z.until!).inDays > 60);
    _p?.setStringList('zones', [for (final z in zones) jsonEncode(z.toJson())]);
    if (lastMove != null) _p?.setInt('lastMove', lastMove!.millisecondsSinceEpoch);
    _p?.setInt('freeEver', freeEver);
    notifyListeners();
    if (sync) _syncLedger();
  }

  /// After a reinstall: the phone's areas come back (free ones stay free, paid passes keep their days),
  /// and the count of free areas ever taken comes back too.
  Future<void> _restoreLedger() async {
    try {
      final r = await DeviceLedger.i.read();
      if (r != null) _takeRecord(r);
    } catch (_) {}
    if (!_ledgerReady.isCompleted) _ledgerReady.complete();
  }

  void _takeRecord(LedgerRecord r) {
    // the phone's record wins; areas only this install has (bought offline) are kept too
    final key = {for (final z in r.zones) '${z.center.latitude},${z.center.longitude},${z.paid}'};
    final extra = zones.where((z) => !key.contains('${z.center.latitude},${z.center.longitude},${z.paid}')).toList();
    zones
      ..clear()
      ..addAll(r.zones)
      ..addAll(extra.where((z) => z.paid));
    freeEver = math.max(freeEver, r.freeEver);
    if (r.lastMove != null && (lastMove == null || r.lastMove!.isAfter(lastMove!))) lastMove = r.lastMove;
    _saveZones(sync: extra.any((z) => z.paid));
  }

  Future<void> _syncLedger() async {
    final server = await DeviceLedger.i.write(LedgerRecord(List.of(zones), lastMove, freeEver));
    if (server != null) _takeRecord(server); // the server may refuse a free area this phone already used
  }

  /// Free areas this phone can still take (2 for the life of the phone; moving one is separate).
  bool get canClaimFree => freeEver < MapZone.maxFree && freeZones.length < MapZone.maxFree;

  /// Where the rider really is (GPS): the first two places become the free areas, by themselves.
  /// Returns true when a new free area was added. A third place always asks for the payment,
  /// even after uninstalling the app or with a new account.
  bool claimFreeZone(LatLng gps, String name) {
    if (unlockedAt(gps) || !canClaimFree) return false;
    zones.add(MapZone(name, gps, added: DateTime.now()));
    freeEver++;
    _saveZones();
    return true;
  }

  /// \$1: 100 miles around [center] for 30 days (a holiday, a trip). Payment is a demo for now.
  void buyZone(LatLng center, String name) {
    zones.add(MapZone(name, center,
        paid: true, added: DateTime.now(), until: DateTime.now().add(const Duration(days: MapZone.passDays))));
    _saveZones();
  }

  bool get canMove => lastMove == null || DateTime.now().difference(lastMove!).inDays >= MapZone.moveEveryDays;

  /// "I moved here": a free area moves to where the rider lives now (once every 90 days).
  bool moveFreeZone(MapZone old, LatLng gps, String name) {
    if (!canMove || old.paid) return false;
    final i = zones.indexOf(old);
    if (i < 0) return false;
    zones[i] = MapZone(name, gps, added: DateTime.now());
    lastMove = DateTime.now();
    _saveZones();
    return true;
  }
}
