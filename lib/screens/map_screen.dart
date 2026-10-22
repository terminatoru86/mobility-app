import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_state.dart';
import '../data/location.dart';
import '../data/open_data.dart';
import '../data/osm.dart';
import '../data/places.dart';
import '../data/routing.dart';
import '../data/store.dart';
import '../data/weather.dart';
import '../data/zones.dart';
import '../theme.dart';
import '../widgets/cluster.dart';
import '../widgets/guide.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart';
import '../widgets/signup.dart';
import '../widgets/tiles.dart';
import 'map_extras.dart';
import 'other_screens.dart' show MyVehicleScreen;
import 'trip_screen.dart';

class MapScreen extends StatefulWidget {
  final AppState state;
  final GlobalKey navKey;
  const MapScreen({super.key, required this.state, required this.navKey});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final _map = MapController();
  double _zoom = 15;
  String? _filter;
  String? _selected;
  bool _showGuide = false;
  bool _weatherFace = false;
  bool _list = false;
  bool _noGps = false;
  Timer? _flip;
  Timer? _pinClock;
  Timer? _chipClock;
  Timer? _debounce;
  Timer? _sosHold;
  double _sosProgress = 0;
  final _osm = OsmService();
  final _open = OpenDataService(); // city halls' bike racks + bikeshare/scooters live, around the map
  Timer? _shareTimer;
  List<Place>? _merged; // all sources together, rebuilt only when one of them changes
  List<Place>? _allCache; // + riders' confirmations and the map settings
  LatLngBounds? _area; // the visible map plus a margin: only pins in here are drawn
  Timer? _areaTimer;
  List<Marker>? _markerCache;
  Object? _markerKey;
  bool _loading = false;
  Weather? _wx;
  GeoResult? _dest; // address picked in search: we show the parking around it

  final _kSearch = GlobalKey();
  final _kFilters = GlobalKey();
  final _kPins = GlobalKey();
  final _kLocate = GlobalKey();
  final _kReport = GlobalKey();
  final _kSos = GlobalKey();

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_storeChanged);
    // The circle in the search bar shows your vehicle, then the weather, every 50 s.
    _flip = Timer.periodic(const Duration(seconds: 50), (_) {
      if (mounted) setState(() => _weatherFace = !_weatherFace);
    });
    // one clock for all pins (glyph <-> age)
    _pinClock = Timer.periodic(const Duration(seconds: 8), (_) => pinShowsAge.value = !pinShowsAge.value);
    _chipClock = Timer.periodic(const Duration(seconds: 2), (_) => chipTick.value++);
    // real places: the cities shipped with the app and the ones saved on the phone (instant),
    // then the visible area from OpenStreetMap
    _osm.loadBundled().then((_) => _osm.loadCache()).then((_) {
      if (mounted) setState(() => _merged = _allCache = null);
      _loadVisible();
    });
    // city halls' racks and live bikeshare around the map (a moment after the map is on screen)
    Future.delayed(const Duration(seconds: 4), () => _loadOpenData(userPos)); // after the map and pins are up
    Future.delayed(const Duration(milliseconds: 300), _loadRegion); // packs inside the app: instant
    _shareTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      if (await _open.refreshSharing() && mounted) setState(() => _merged = _allCache = null);
    });
    _loadWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _locate(); // start where the rider is, anywhere in the US
      if (!widget.state.guideDone) {
        setState(() => _showGuide = true);
      } else if (widget.state.shouldInvite) {
        await showSignupInvite(context, widget.state);
        if (mounted) setState(() {});
      }
    });
  }

  void _storeChanged() {
    if (mounted) setState(() => _allCache = null);
  }

  /// Called while the map moves: the pins are recalculated only when the view
  /// leaves the area already prepared (the visible map plus half of it on each side).
  // ── map areas: outside the rider's areas the map is locked ──
  bool _locked = false;
  String? _lockName;
  LatLng? _lockAt;
  Timer? _lockTimer;

  void _checkLock(LatLng center) {
    final st = Store.i;
    final locked = st.zones.isNotEmpty && !st.unlockedAt(center);
    if (locked == _locked && (!locked || _lockAt != null && const Distance()(_lockAt!, center) < 30000)) return;
    setState(() {
      _locked = locked;
      _lockAt = locked ? center : null;
      if (!locked) _lockName = null;
    });
    if (locked) {
      _lockTimer?.cancel();
      _lockTimer = Timer(const Duration(milliseconds: 600), () async {
        final n = await cityName(center);
        if (mounted && _lockAt == center) setState(() => _lockName = n);
      });
    }
  }

  /// The first two places where the rider really is become the free areas.
  Future<void> _claimZone(LatLng gps) async {
    final st = Store.i;
    await st.ledgerReady.timeout(const Duration(seconds: 12), onTimeout: () {}); // the phone's record first
    if (st.unlockedAt(gps) || !st.canClaimFree) return;
    final n = await cityName(gps) ?? 'My area';
    if (st.claimFreeZone(gps, n) && mounted) {
      setState(() => _merged = _allCache = null);
      try {
        _checkLock(_map.camera.center);
      } catch (_) {}
    }
  }

  Future<void> _unlockHere(LatLng at, String? name) async {
    final n = name ?? await cityName(at) ?? 'This area';
    if (!mounted) return;
    final ok = await showUnlockSheet(context, n);
    if (ok == true) {
      Store.i.buyZone(at, n);
      setState(() {
        _locked = false;
        _lockAt = null;
        _merged = _allCache = null;
      });
      _loadOpenData(at);
      _loadVisible();
    }
  }

  void _watchArea(MapCamera cam) {
    _checkLock(cam.center);
    final v = cam.visibleBounds;
    final a = _area;
    if (a != null && a.contains(v.southWest) && a.contains(v.northEast)) return;
    _areaTimer?.cancel();
    _areaTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final dLat = (v.north - v.south) * 0.3, dLng = (v.east - v.west) * 0.3;
      setState(() => _area = LatLngBounds(
            LatLng(v.south - dLat, v.west - dLng),
            LatLng(v.north + dLat, v.east + dLng),
          ));
    });
  }

  @override
  void dispose() {
    Store.i.removeListener(_storeChanged);
    _shareTimer?.cancel();
    _pieceTimer?.cancel();
    _lockTimer?.cancel();
    _ringTimer?.cancel();
    _areaTimer?.cancel();
    _flip?.cancel();
    _pinClock?.cancel();
    _chipClock?.cancel();
    _debounce?.cancel();
    _sosHold?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    final w = await fetchWeather(userPos);
    if (mounted && w != null) setState(() => _wx = w);
  }

  /// Real places (OpenStreetMap), with what riders confirmed in Stats; demo places only until they arrive.
  bool _openBusy = false;
  DateTime _lastPiece = DateTime(2000);
  Timer? _pieceTimer;

  /// Every place within 100 miles (the rider's areas): loaded quietly, piece by piece, nearest first.
  Future<void> _loadRegion() async {
    final st = Store.i;
    final centers = st.zones.where((z) => z.active).map((z) => z.center).toList();
    if (centers.isEmpty) centers.add(userPos);
    const d = Distance();
    centers.sort((a, b) => d(userPos, a).compareTo(d(userPos, b)));
    for (final c in centers) {
      if (!mounted) return;
      await _osm.loadRegion(c, MapZone.radiusMiles.toDouble(), () {
        // redraw at most every 2.5 s while pieces arrive
        if (!mounted) return;
        final since = DateTime.now().difference(_lastPiece).inMilliseconds;
        _pieceTimer?.cancel();
        _pieceTimer = Timer(Duration(milliseconds: since > 2500 ? 0 : 2500 - since), () {
          if (!mounted) return;
          _lastPiece = DateTime.now();
          setState(() => _merged = _allCache = null);
        });
      });
    }
  }


  /// Official racks of the city around [at] and the share systems of that city.
  Future<void> _loadOpenData(LatLng at) async {
    if (_openBusy || !mounted) return;
    if (Store.i.zones.isNotEmpty && !Store.i.unlockedAt(at)) return; // locked area: nothing is loaded
    _openBusy = true;
    try {
      await _osm.packIndex(); // city lists already in the packs are not downloaded again
      final a = await _open.loadCitiesAround(at);
      final b = await _open.chooseSystemsAround(at);
      if ((a || b) && mounted) setState(() => _merged = _allCache = null);
    } finally {
      _openBusy = false;
    }
  }

  /// OpenStreetMap + city halls' racks (not where OSM already has one, ~15 m) + live bikeshare
  /// (instead of the copies of the same operators in OSM).
  List<Place> get _sources {
    final m = _merged;
    if (m != null) return m;
    final cell = <String>{};
    String key(LatLng p, int dy, int dx) => '${(p.latitude * 6000).round() + dy}:${(p.longitude * 6000).round() + dx}';
    final out = <Place>[];
    final live = _open.liveOperators;
    for (final p in _osm.places.values) {
      if (p.type == PlaceType.sharing && live.any((o) => (p.operatorName ?? p.address).toLowerCase().contains(o))) continue;
      out.add(p);
      if (p.type.group == 'Parking') cell.add(key(p.pos, 0, 0));
    }
    for (final p in _open.cityRacks.values) {
      var dup = false;
      if (p.type.group != 'Parking') {
        // national bikeshare list only where no live feed is loaded
        if (p.type != PlaceType.sharing || _open.sharing.isEmpty) out.add(p);
        continue;
      }
      for (final dy in const [-1, 0, 1]) {
        for (final dx in const [-1, 0, 1]) {
          if (cell.contains(key(p.pos, dy, dx))) dup = true;
        }
      }
      if (!dup) out.add(p);
    }
    out.addAll(_open.sharing.values);
    return _merged = out;
  }

  List<Place> get _all {
    final c = _allCache;
    if (c != null && _merged != null) return c;
    final src = _sources;
    final base = src.isEmpty ? demoPlaces : src;
    final conf = Store.i.confirmations;
    return _allCache = [
      for (final p in base)
        if (Store.i.showOnMap[p.type] ?? true)
          conf.containsKey(p.id) ? p.withStatus(conf[p.id]!.status, '<5 min') : p,
    ];
  }

  List<Place> get _visible {
    final all = _all;
    return _filter == null ? all : all.where((p) => p.type.chip == _filter).toList();
  }

  List<Place> _near(LatLng c, double meters) {
    const d = Distance();
    final out = _all.where((p) => d(c, p.pos) < meters).toList()
      ..sort((a, b) => d(c, a.pos).compareTo(d(c, b.pos)));
    return out;
  }

  /// GPS: move the map to the rider. Without GPS the map stays on Chicago.
  Future<void> _locate() async {
    final pos = await currentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() => _noGps = true);
      _map.move(userPos, 16.2);
      _claimZone(userPos); // no GPS: the area where the map opens
      return;
    }
    userPos = pos;
    _ringCenter = pos;
    _claimZone(pos);
    _osm.refreshDistances();
    _open.refreshDistances();
    _loadOpenData(pos);
    _loadRegion();
    setState(() {
      _noGps = false;
      _merged = _allCache = null;
    });
    _map.move(pos, 16.2);
    _loadWeather();
  }

  /// Trip: choose the route, then GO for the GPS guidance.
  Future<void> _trip(Place p) async {
    if (Store.i.zones.isNotEmpty && !Store.i.unlockedAt(p.pos)) return _unlockHere(p.pos, null);
    await startTrip(
      context,
      to: p.pos,
      toName: p.address,
      place: p,
      nearby: _near(p.pos, 2500).take(80).toList(),
      myVehicle: widget.state.myVehicle,
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSearch() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SearchSheet(places: _all),
    );
    if (!mounted || picked == null) return;
    if (picked is Place) {
      _map.move(picked.pos, 17);
      _openPlace(picked);
    } else if (picked is GeoResult) {
      _showDestination(picked);
    } else if (picked is String) {
      setState(() => _filter = picked);
    }
  }

  // ── Searched address: normal destination, plus a suggestion if a rack is 300 m or closer ──
  Place? _destRack;
  List<LatLng> _destWalk = const [];

  Future<void> _showDestination(GeoResult g) async {
    final rack = Store.i.parkNearDest ? parkingNear(g.pos) : null;
    setState(() {
      _dest = g;
      _destRack = rack;
      _destWalk = rack == null ? const [] : [g.pos, rack.pos];
    });
    _map.move(g.pos, 16.5);
    if (rack != null) {
      final path = await footPath(g.pos, rack.pos);
      if (mounted && _destRack == rack) setState(() => _destWalk = path);
    }
  }

  void _clearDestination() => setState(() {
        _dest = null;
        _destRack = null;
        _destWalk = const [];
      });

  Future<void> _tripToDest() async {
    final d = _dest!;
    if (Store.i.zones.isNotEmpty && !Store.i.unlockedAt(d.pos)) return _unlockHere(d.pos, null);
    await startTrip(
      context,
      to: d.pos,
      toName: d.title,
      nearby: _near(d.pos, 2500).take(80).toList(),
      myVehicle: widget.state.myVehicle,
    );
    if (mounted) setState(() {});
  }

  Widget _destCard() {
    final d = _dest!;
    final rack = _destRack;
    final m = rack == null ? 0.0 : const Distance()(d.pos, rack.pos);
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flag_rounded, color: AppColors.red, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                if (d.subtitle.isNotEmpty)
                  Text(d.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.soft)),
              ]),
            ),
            FilledButton.icon(
              onPressed: _tripToDest,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Trip'),
              style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
            ),
            IconButton(onPressed: _clearDestination, icon: const Icon(Icons.close)),
          ]),
          if (rack != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _openPlace(rack),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Glyph(rack.type, size: 20, color: colorsFor(rack.shownStatus).dark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Suggestion: ${rack.type.title.toLowerCase()} ${m.round()} m away · ${(m / 80).ceil()} min walk',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.soft),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  bool _loadAgain = false; // the map moved while loading: load the new place right after

  Future<void> _loadVisible() async {
    if (!mounted) return;
    if (_loading) {
      _loadAgain = true;
      return;
    }
    MapCamera? cam;
    try {
      cam = _map.camera;
    } catch (_) {
      cam = null; // map not ready yet
    }
    if (cam == null) return;
    if (Store.i.zones.isNotEmpty && !Store.i.unlockedAt(cam.center)) return; // locked area
    // always the whole ring (so every place inside it is there), plus the screen when zoomed in
    final rc = _ringCenter ?? cam.center;
    final rLat = kRingMiles * 1.609 / 111.2, rLng = rLat / math.cos(rc.latitude * math.pi / 180);
    var s0 = rc.latitude - rLat, w0 = rc.longitude - rLng, n0 = rc.latitude + rLat, e0 = rc.longitude + rLng;
    if (cam.zoom >= 12) {
      final v = cam.visibleBounds;
      s0 = math.min(s0, v.south);
      w0 = math.min(w0, v.west);
      n0 = math.max(n0, v.north);
      e0 = math.max(e0, v.east);
    }
    setState(() => _loading = true);
    _loadOpenData(cam.center);
    final changed = await _osm.loadArea(s0, w0, n0, e0);
    if (!mounted) return;
    setState(() => _loading = false);
    if (changed) setState(() => _merged = _allCache = null);
    if (_loadAgain) {
      _loadAgain = false;
      _loadVisible();
    }
  }

  Future<void> openPlace(Place p) => _openPlace(p);

  Future<void> _openPlace(Place p) async {
    setState(() => _selected = p.id);
    if (p.type == PlaceType.sharing && !widget.state.sharingChosen) {
      await chooseOperators(context);
      await widget.state.setSharingChosen();
      if (!mounted) return;
    }
    await showPlaceSheet(
      context,
      p,
      myVehicle: widget.state.myVehicle,
      showVehicleTip: !widget.state.sheetTipDone,
      onTipSeen: widget.state.setSheetTipDone,
      onTrip: () => _trip(p),
      state: widget.state,
    );
    if (mounted) setState(() => _selected = null);
  }

  /// Radius of the ring in the middle of the map: inside it our pins (and groups where they overlap), outside light dots.
  static const kRingMiles = 3.0; // 6 miles across

  /// The ring follows the middle of the map: what comes in on one side becomes pins/groups,
  /// what leaves on the other side turns into dots.
  LatLng? _ringCenter;
  DateTime _ringMoved = DateTime(2000);
  Timer? _ringTimer;

  void _moveRing(LatLng c, double zoom) {
    final rc = _ringCenter ?? userPos;
    // how far the middle moved, compared with what is on screen
    final mPerPx = 156543.03 * math.cos(c.latitude * math.pi / 180) / math.pow(2, zoom);
    final moved = const Distance()(rc, c) / mPerPx; // pixels
    if (moved < 110) return;
    void apply() {
      if (!mounted) return;
      setState(() => _ringCenter = c);
      _ringMoved = DateTime.now();
    }

    _ringTimer?.cancel();
    // while dragging: at most ~4 updates a second; the last one when the map stops
    if (DateTime.now().difference(_ringMoved).inMilliseconds > 450) {
      apply();
    } else {
      _ringTimer = Timer(const Duration(milliseconds: 220), apply);
    }
  }

  /// From this zoom the real pins appear (the map opens here).
  static const kPinZoom = 15.5;

  /// From this zoom up: every place is its own pin, never grouped.
  static const kAllPinsZoom = 15.0;

  /// Below [kAllPinsZoom], groups start only when more than this many pins would be on the map.
  static const kGroupAbove = 120;

  /// Pins are real widgets (heavy); dots are painted in one go (light).
  List<CircleMarker> _dotCache = const [];
  List<Place> _dotPlaces = const [];

  List<Marker> _markers() {
    final all = _all;
    final key = (identityHashCode(all), _filter, _selected, _zoom, _area, Store.i.zones.length,
        _ringCenter ?? userPos);
    if (_markerCache != null && key == _markerKey) return _markerCache!;
    _markerKey = key;
    _buildLayers();
    return _markerCache!;
  }

  void _buildLayers() {
    try {
      _screen = _map.camera.visibleBounds;
    } catch (_) {
      _screen = null;
    }
    final a = _area;
    final st = Store.i;
    // quick flat-earth test against the rider's areas (thousands of places, a few areas)
    final zs = [for (final z in st.zones.where((z) => z.active)) z.center];
    bool inZone(LatLng p) {
      for (final c in zs) {
        final dy = (p.latitude - c.latitude) * 111.2;
        final dx = (p.longitude - c.longitude) * 111.2 * math.cos(c.latitude * math.pi / 180);
        if (dx * dx + dy * dy <= 160.9 * 160.9) return true;
      }
      return false;
    }

    final pins = _visible
        .where((p) => (a == null || a.contains(p.pos)) && (st.zones.isEmpty || inZone(p.pos)))
        .toList();
    final markers = <Marker>[];
    final dots = <Place>[];

    // the ring: 6 miles across, in the middle of the map. Inside: our pins (groups where they overlap).
    // Outside: light dots only.
    final rc = _ringCenter ?? userPos;
    final kx = 111.2 * math.cos(rc.latitude * math.pi / 180);
    double km2(LatLng p) {
      final dy = (p.latitude - rc.latitude) * 111.2, dx = (p.longitude - rc.longitude) * kx;
      return dx * dx + dy * dy;
    }

    const ringKm = kRingMiles * 1.609;
    final inside = <Place>[];
    for (final p in pins) {
      (km2(p.pos) <= ringKm * ringKm ? inside : dots).add(p);
    }

    // inside the ring: our real pins with their info. Zoomed in (15+) they are never grouped.
    // Zoomed out, and only when there are too many, pins that would sit on each other become a group.
    final mPerPx = 156543.03 * math.cos(rc.latitude * math.pi / 180) / math.pow(2, _zoom);
    Map<String, List<Place>> cells = {};
    if (_zoom >= kAllPinsZoom || inside.length <= kGroupAbove) {
      for (final p in inside) {
        cells[p.id] = [p];
      }
    } else {
      var cellPx = 42.0;
      for (int round = 0; round < 6; round++) {
        final cellLat = cellPx * mPerPx / 111200;
        final cellLng = cellLat / math.max(0.2, math.cos(rc.latitude * math.pi / 180));
        cells = {};
        for (final p in inside) {
          cells.putIfAbsent('${(p.pos.latitude / cellLat).floor()}:${(p.pos.longitude / cellLng).floor()}', () => []).add(p);
        }
        if (cells.length <= 160) break;
        cellPx *= 1.5;
      }
    }
    for (final group in cells.values) {
      if (group.length == 1) {
        markers.add(_pinMarker(group.first));
        continue;
      }
      final lat = group.map((p) => p.pos.latitude).reduce((x, y) => x + y) / group.length;
      final lng = group.map((p) => p.pos.longitude).reduce((x, y) => x + y) / group.length;
      final size = (30 + 14 * math.log(group.length) / math.ln10).clamp(32.0, 54.0).toDouble();
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: size,
        height: size,
        child: GestureDetector(
          onTap: () => _openGroup(group),
          child: DonutCluster(places: group, size: size),
        ),
      ));
    }
    final sel = _selected;
    if (sel != null) {
      final s = dots.where((p) => p.id == sel).firstOrNull;
      if (s != null) {
        dots.remove(s);
        markers.add(_pinMarker(s));
      }
    }
    // far out there can be tens of thousands of dots: keep one per few px (the map stays fluid)
    void thinOut(List<Place> list, double px, int above) {
      if (list.length <= above) return;
      final cell = px * mPerPx / 111200;
      final cellLng = cell / math.max(0.2, math.cos(rc.latitude * math.pi / 180));
      final seen = <int>{};
      final thin = <Place>[];
      for (final p in list) {
        final k = (p.pos.latitude / cell).floor() * 1000003 + (p.pos.longitude / cellLng).floor();
        if (seen.add(k)) thin.add(p);
      }
      list
        ..clear()
        ..addAll(thin);
    }

    thinOut(dots, 4, 2500);
    // a filter is on (e.g. Rack): the other places stay on the map as tiny coloured dots,
    // smaller than the dots outside the ring, so the chosen kind stands out
    final others = _filter == null
        ? <Place>[]
        : _all
            .where((p) =>
                p.type.chip != _filter && (a == null || a.contains(p.pos)) && (st.zones.isEmpty || inZone(p.pos)))
            .toList();
    thinOut(others, 3, 1500);
    _dotPlaces = [...dots, ...others];
    final r = _zoom < 11 ? 2.6 : (_zoom < 14 ? 3.4 : 4.6);
    // a bit smaller than the dots outside the ring, but solid and clearly visible on the calm map
    final small = math.max(2.8, r * 0.75);
    // shops, service, rent have no live status: dark slate (light grey would vanish on the grey map)
    Color dotColor(Place p) =>
        p.shownStatus == Status.neutral || p.shownStatus == Status.unknown ? AppColors.slate : colorsFor(p.shownStatus).main;
    _dotCache = [
      for (final p in others)
        CircleMarker(
          point: p.pos,
          radius: small,
          color: dotColor(p),
          borderColor: Colors.white,
          borderStrokeWidth: 1.2,
        ),
      for (final p in dots)
        CircleMarker(
          point: p.pos,
          radius: r,
          color: dotColor(p).withValues(alpha: 0.95),
          borderColor: Colors.white,
          borderStrokeWidth: _zoom < 11 ? 0.8 : 1.4,
        ),
    ];
    _markerCache = markers;
  }

  /// Tap on a group: fly to exactly those places, close enough to see each pin with its info.
  void _openGroup(List<Place> group) {
    final pts = group.map((p) => p.pos).toList();
    final b = LatLngBounds.fromPoints(pts);
    final tiny = (b.north - b.south).abs() < 0.0003 && (b.east - b.west).abs() < 0.0003;
    try {
      if (tiny) {
        _map.move(b.center, 19);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: b, padding: const EdgeInsets.fromLTRB(60, 190, 60, 140), maxZoom: 19));
        if (_map.camera.zoom < kAllPinsZoom) _map.move(b.center, kAllPinsZoom); // close enough: no groups
      }
    } catch (_) {}
  }

  /// A tap on the map opens the dot under the finger (within ~22 px).
  void _tapDot(LatLng at) {
    if (_dotPlaces.isEmpty) return;
    double zoom;
    try {
      zoom = _map.camera.zoom;
    } catch (_) {
      return;
    }
    final mPerPx = 156543.03 * math.cos(at.latitude * math.pi / 180) / math.pow(2, zoom);
    const d = Distance();
    Place? best;
    var bestM = 22 * mPerPx;
    for (final p in _dotPlaces) {
      final m = d(at, p.pos);
      if (m < bestM) {
        bestM = m;
        best = p;
      }
    }
    if (best != null) _openPlace(best);
  }

  /// What the rider sees right now (pins outside it do not take turns).
  LatLngBounds? _screen;
  bool _onScreen(LatLng p) => _screen == null || _screen!.contains(p);

  Marker _pinMarker(Place p) => Marker(
        point: p.pos,
        width: PlacePin.width,
        height: PlacePin.height,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _openPlace(p),
          child: PlacePin(place: p, selected: _selected == p.id, small: _zoom < 15, animate: _onScreen(p.pos)),
        ),
      );

  // SOS: hold 3 seconds.
  void _sosDown() {
    if (Store.i.sosActive) return;
    _sosHold?.cancel();
    setState(() => _sosProgress = 0);
    _sosHold = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _sosProgress = t.tick * 50 / 3000);
      if (_sosProgress >= 1) {
        t.cancel();
        setState(() => _sosProgress = 0);
        showSosComposer(context);
      }
    });
  }

  void _sosUp() {
    _sosHold?.cancel();
    if (mounted && _sosProgress > 0) setState(() => _sosProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final store = Store.i;
    final rainIn = _wx?.rainInMinutes;
    knownPlaces = _all;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: userPos,
          initialZoom: 16.2,
          minZoom: 3,
          maxZoom: 19,
          onMapReady: () => _watchArea(_map.camera),
          onTap: (_, at) => _tapDot(at),
          onPositionChanged: (camera, hasGesture) {
            // rebuild the pins only when the zoom crosses a half step, not on every frame
            final bucket = (camera.zoom * 2).floor() / 2;
            if (bucket != _zoom) setState(() => _zoom = bucket);
            _watchArea(camera);
            _moveRing(camera.center, camera.zoom);
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 700), _loadVisible);
          },
        ),
        children: [
          if (store.satellite) satelliteTiles() else if (store.bikeMap) bikeTiles() else baseTiles(),
          if (store.sosActive)
            CircleLayer(circles: [
              CircleMarker(
                point: userPos,
                radius: 3219, // 2 miles
                useRadiusInMeter: true,
                color: AppColors.red.withValues(alpha: 0.10),
                borderColor: AppColors.red,
                borderStrokeWidth: 2,
              ),
            ]),
          if (store.incomingSos != null)
            CircleLayer(circles: [
              CircleMarker(
                point: store.incomingSos!.pos,
                radius: 220, // approximate area
                useRadiusInMeter: true,
                color: AppColors.red.withValues(alpha: 0.14),
                borderColor: AppColors.red.withValues(alpha: 0.6),
                borderStrokeWidth: 1.5,
              ),
              CircleMarker(point: store.incomingSos!.pos, radius: 7, color: AppColors.red, borderColor: Colors.white, borderStrokeWidth: 2.5),
            ]),
          if (store.sosActive && store.sosHelper != null) ...[
            PolylineLayer(polylines: [
              Polyline(
                points: [store.sosHelper!.pos, userPos],
                strokeWidth: 4,
                color: AppColors.green,
                pattern: const StrokePattern.dotted(spacingFactor: 2),
              ),
            ]),
            CircleLayer(circles: [
              CircleMarker(point: store.sosHelper!.pos, radius: 8, color: AppColors.green, borderColor: Colors.white, borderStrokeWidth: 3),
            ]),
          ],
          if (_destWalk.length > 1)
            PolylineLayer(polylines: [
              Polyline(
                points: _destWalk,
                strokeWidth: 5,
                color: AppColors.blue,
                pattern: const StrokePattern.dotted(spacingFactor: 2),
              ),
            ]),
          // the ring (6 miles across) in the middle of the map
          CircleLayer(circles: [
            CircleMarker(
              point: _ringCenter ?? userPos,
              radius: kRingMiles * 1609.34,
              useRadiusInMeter: true,
              color: AppColors.blue.withValues(alpha: 0.035),
              borderColor: Colors.transparent,
            ),
          ]),
          PolylineLayer(polylines: [
            Polyline(
              points: ringPoints(_ringCenter ?? userPos, kRingMiles * 1609.34),
              strokeWidth: 2,
              color: AppColors.blue.withValues(alpha: 0.55),
              pattern: const StrokePattern.dotted(spacingFactor: 2.2),
            ),
          ]),
          if (_zoom < 14)
            MarkerLayer(markers: [
              Marker(
                point: LatLng((_ringCenter ?? userPos).latitude + kRingMiles * 1.609 / 111.2, (_ringCenter ?? userPos).longitude),
                width: 70,
                height: 24,
                child: const RingLabel(text: '6 mi'),
              ),
            ]),
          if (_zoom < 9)
            CircleLayer(circles: [
              for (final z in store.zones.where((z) => z.active))
                CircleMarker(
                  point: z.center,
                  radius: MapZone.radiusMeters,
                  useRadiusInMeter: true,
                  color: (z.paid ? AppColors.yellow : AppColors.blue).withValues(alpha: 0.07),
                  borderColor: z.paid ? AppColors.yellowDark : AppColors.blue,
                  borderStrokeWidth: 1.5,
                ),
            ]),
          Builder(builder: (_) {
            _markers(); // makes sure the dots are up to date
            return CircleLayer(circles: _dotCache);
          }),
          MarkerLayer(markers: [
            if (_dest != null)
              Marker(
                point: _dest!.pos,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.flag_rounded, color: AppColors.red, size: 34),
              ),
            for (final r in store.reports.where((r) => r.onMap))
              Marker(
                point: r.pos,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: r.kind == 'I like this lane' ? AppColors.greenTint : AppColors.yellow,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(r.icon, size: 16, color: AppColors.ink),
                ),
              ),
            Marker(point: userPos, width: 34, height: 34, child: const UserDot()),
            ..._markers(),
          ]),
        ],
      ),
      if (_list)
        Positioned.fill(
          child: Container(
            color: AppColors.paper,
            padding: EdgeInsets.only(top: top + 112),
            child: PlacesList(places: _near(userPos, 1500).take(60).toList(), onOpen: _openPlace),
          ),
        ),
      // spotlight target for the "how to read pins" step
      Positioned(left: 20, top: top + 160, child: SizedBox(key: _kPins, width: 70, height: 80)),
      Positioned(
        left: 12,
        right: 12,
        top: top + 8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _searchBar(),
          const SizedBox(height: 8),
          _filters(),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _mapListToggle(),
            if (rainIn != null)
              _pill(Icons.umbrella, 'Rain in $rainIn min', AppColors.blue, Colors.white, () => showWeather(context, _wx!)),
            if (_loading)
              _pill(null, 'Loading places…', Colors.white, AppColors.ink, null)
            else if (_osm.lastError != null)
              _pill(Icons.refresh, 'Places not loaded · retry', AppColors.redTint, AppColors.redDark, _loadVisible),
            if (_noGps)
              _pill(Icons.location_disabled, '${gpsProblem ?? 'Turn on location'} · retry', Colors.white, AppColors.ink, _locate),
            // the region (100 miles) still filling in, piece by piece
            ValueListenableBuilder<(int, int)?>(
              valueListenable: _osm.regionProgress,
              builder: (_, p, __) => p == null
                  ? const SizedBox.shrink()
                  : _pill(null, 'Area ${(p.$1 * 100 / p.$2).round()}% · ${p.$1}/${p.$2}', Colors.white, AppColors.ink, null),
            ),
          ]),
        ]),
      ),
      if (_dest != null && !_list)
        Positioned(
          left: 10,
          right: 10,
          bottom: 14,
          child: _destCard(),
        ),
      if (!_list)
        Positioned(
          right: 14,
          bottom: _dest != null ? (_destRack != null ? 160 : 112) : 24,
          child: Column(children: [
            GestureDetector(
              key: _kLocate,
              onDoubleTap: store.nextMapStyle,
              child: _roundBtn(Icons.my_location, Colors.white, AppColors.ink, _locate),
            ),
            const SizedBox(height: 12),
            _roundBtn(Icons.add, AppColors.primary, Colors.white, () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportMenu(pos: userPos)));
            }, key: _kReport),
          ]),
        ),
      Positioned(left: 14, bottom: _dest != null ? (_destRack != null ? 166 : 118) : 30, child: _sosButton()),
      if (_locked && !_list)
        Positioned(
          left: 12,
          right: 12,
          bottom: 92,
          child: LockedAreaCard(
            name: _lockName,
            freeNames: [for (final z in store.zones.where((z) => z.active)) z.name],
            onUnlock: () => _unlockHere(_lockAt ?? userPos, _lockName),
          ),
        ),
      if (store.incomingSos != null && _dest == null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 140,
          child: SosNote(
            sos: store.incomingSos!,
            onHelp: () {
              final s = store.incomingSos!;
              store.dismissIncomingSos();
              startTrip(context, to: s.pos, toName: 'SOS · rider in need', myVehicle: widget.state.myVehicle);
            },
          ),
        ),
      if (store.sosActive && store.sosHelper != null && _dest == null)
        Positioned(left: 12, right: 12, bottom: 140, child: SosHelperCard(helper: store.sosHelper!)),
      Positioned(
        right: 4,
        bottom: 2,
        child: Text(
            store.satellite
                ? '© Esri World Imagery'
                : store.bikeMap
                    ? '© OpenStreetMap contributors · CyclOSM'
                    : '© OpenStreetMap contributors',
            style: const TextStyle(fontSize: 9, color: AppColors.soft)),
      ),
      if (_showGuide)
        Positioned.fill(
          child: GuideOverlay(
            total: 8,
            steps: [
              GuideStep(_kSearch, 'Search, vehicle and weather',
                  'Type an address or a place. The circle on the left turns: once your vehicle, once the weather. Tap it for rain and wind.'),
              GuideStep(_kFilters, 'Quick filters', 'Tap a filter to see only parking, charging, service or shops. Tap again to see everything.'),
              GuideStep(_kPins, 'How to read the pins', 'The colour is the status. Inside the pin, the drawing and the time since the last update take turns.',
                  extra: const MiniLegend()),
              GuideStep(_kLocate, 'Where you are', 'One tap brings you back. Two taps switch the map: road, bike map, satellite.'),
              GuideStep(_kReport, 'Report', 'Saw a pothole, a new place or a broken pump? Press + and tell the community.'),
              GuideStep(_kSos, 'SOS', 'Hold for 3 seconds to ask riders nearby for help. Works without an account.'),
              GuideStep(widget.navKey, 'Bottom menu', 'Routes, Health, Community and Profile. Replay this guide any time from Profile → Help.'),
            ],
            onFinish: () async {
              setState(() => _showGuide = false);
              await widget.state.setGuideDone();
            },
          ),
        ),
    ]);
  }

  Widget _sosButton() {
    final active = Store.i.sosActive;
    return Listener(
      key: _kSos,
      onPointerDown: (_) => _sosDown(),
      onPointerUp: (_) => _sosUp(),
      onPointerCancel: (_) => _sosUp(),
      child: GestureDetector(
      onTap: active ? Store.i.cancelSos : null,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: AppColors.red.withValues(alpha: 0.25 + _sosProgress * 0.5), blurRadius: 12 + _sosProgress * 16),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            if (active) ...[
              const SizedBox(width: 8),
              const Icon(Icons.close, color: Colors.white, size: 18),
            ],
          ]),
        ),
        if (Store.i.incomingSos != null && !active)
          Positioned(
            right: -4,
            top: -6,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.red, width: 2),
              ),
              child: const Text('1', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ),
        if (_sosProgress > 0)
          Positioned(
            left: 4,
            right: 4,
            bottom: 3,
            child: LinearProgressIndicator(
              value: _sosProgress,
              minHeight: 3,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
      ]),
      ),
    );
  }

  Widget _pill(IconData? icon, String text, Color bg, Color fg, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)] else ...[
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
              const SizedBox(width: 6),
            ],
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
          ]),
        ),
      );

  Widget _mapListToggle() => Container(
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (label, isList) in const [('Map', false), ('List', true)])
            GestureDetector(
              onTap: () => setState(() => _list = isList),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _list == isList ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: _list == isList ? Colors.white : AppColors.soft)),
              ),
            ),
        ]),
      );

  Widget _searchBar() => GestureDetector(
        onTap: _openSearch,
        child: Container(
          key: _kSearch,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(27),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(children: [
            GestureDetector(
              // vehicle side → My vehicle; weather side → rain and wind
              onTap: () async {
                if (!_weatherFace) {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => MyVehicleScreen(state: widget.state)));
                  if (mounted) setState(() {});
                } else if (_wx != null) {
                  showWeather(context, _wx!);
                } else {
                  _loadWeather();
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Container(
                  key: ValueKey(_weatherFace),
                  width: 64,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _weatherFace ? const Color(0xFFE6EEFB) : AppColors.paper,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(color: _weatherFace ? AppColors.blue : AppColors.slate, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: _weatherFace
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(_wxIcon(), size: 18, color: AppColors.blue),
                          const SizedBox(width: 3),
                          Text(_wx == null ? '--°' : '${_wx!.temp.round()}°',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.blue)),
                        ])
                      : Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset((widget.state.myVehicle ?? Vehicle.bike).asset),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_dest?.title ?? 'Search address or place',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _dest == null ? AppColors.soft : AppColors.ink,
                    fontSize: 16,
                    fontWeight: _dest == null ? FontWeight.w400 : FontWeight.w800,
                  )),
            ),
            if (_dest != null) IconButton(onPressed: _clearDestination, icon: const Icon(Icons.close)),
          ]),
        ),
      );

  IconData _wxIcon() {
    final s = _wx?.sky ?? 'Cloudy';
    return switch (s) {
      'Clear' => Icons.wb_sunny_outlined,
      'Rain' || 'Showers' => Icons.umbrella_outlined,
      'Snow' => Icons.ac_unit,
      'Storm' => Icons.thunderstorm_outlined,
      _ => Icons.wb_cloudy_outlined,
    };
  }

  Widget _filters() => SingleChildScrollView(
        key: _kFilters,
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in kFilterChips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _filter = _filter == f.$1 ? null : f.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _filter == f.$1 ? AppColors.slateTint : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filter == f.$1 ? AppColors.primary : Colors.transparent, width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Row(children: [
                    // groups with several drawings show them in turn, every 2 seconds
                    if (f.$2.length == 1)
                      Glyph(f.$2.first, size: 16, color: AppColors.primary)
                    else
                      ValueListenableBuilder<int>(
                        valueListenable: chipTick,
                        builder: (_, t, __) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (c, a) => FadeTransition(
                            opacity: a,
                            child: ScaleTransition(scale: Tween(begin: .7, end: 1.0).animate(a), child: c),
                          ),
                          child: Glyph(f.$2[t % f.$2.length],
                              key: ValueKey(f.$2[t % f.$2.length]), size: 16, color: AppColors.primary),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
        ]),
      );

  Widget _roundBtn(IconData i, Color bg, Color fg, VoidCallback onTap, {Key? key}) => Material(
        key: key,
        color: bg,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(i, color: fg)),
        ),
      );
}

/// Ticks every 2 s: the filter chips with several drawings show the next one (only the chip redraws).
final ValueNotifier<int> chipTick = ValueNotifier(0);

/// The quick filters at the top of the map, in this order; each shows all the drawings of its group.
const kFilterChips = <(String, List<PlaceType>)>[
  ('Rack', [PlaceType.rack]),
  ('Parking', [PlaceType.parkOutdoor, PlaceType.parkCovered, PlaceType.parkPrivate]),
  ('Charging', [PlaceType.charging]),
  ('Service', [PlaceType.service, PlaceType.pump, PlaceType.selfService]),
  ('Sharing', [PlaceType.sharing, PlaceType.rent]),
  ('Wash', [PlaceType.wash]),
  ('Shop', [PlaceType.shop]),
];

/// First tap on a sharing pin (and Profile → Sharing): pick the operators to show, filtered by GPS.
Future<void> chooseOperators(BuildContext context) async {
  final chosen = {for (final o in demoOperators) o.name: Store.i.operators.contains(o.name)};
  String priceFilter = 'All';
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        var ops = demoOperators.toList();
        if (priceFilter == '≤ \$0.35/min') ops = ops.where((o) => o.price.contains('0.19') || o.price.contains('0.3')).toList();
        if (priceFilter == 'Cheapest first') ops.sort((a, b) => a.price.compareTo(b.price));
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Which sharing on the map?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'Near you: Chicago', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' (GPS) · tick what you want on the map'),
            ]), style: TextStyle(fontSize: 12, color: AppColors.soft)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final f in ['All', '≤ \$0.35/min', 'Cheapest first'])
                ChoiceChip(label: Text(f), selected: priceFilter == f, onSelected: (_) => set(() => priceFilter = f)),
            ]),
            const SizedBox(height: 6),
            for (final o in ops)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: chosen[o.name],
                onChanged: (v) => set(() => chosen[o.name] = v ?? false),
                title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                subtitle: Text(o.price, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const Center(
              child: Text('All operators in the US (70+) ›', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                Store.i.setOperators({for (final e in chosen.entries) if (e.value) e.key});
                Navigator.pop(ctx);
              },
              child: Text('Done · ${chosen.values.where((v) => v).length} operators'),
            ),
          ]),
        );
      },
    ),
  );
}

/// Search: recent, saved and categories; while typing, our places first, then US addresses.
class _SearchSheet extends StatefulWidget {
  final List<Place> places;
  const _SearchSheet({required this.places});
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  Timer? _wait;
  List<GeoResult> _results = [];
  List<Place> _ours = [];
  String _q = '';
  bool _busy = false;

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _q = q.trim();
    final low = _q.toLowerCase();
    setState(() {
      _ours = low.length < 2
          ? []
          : widget.places.where((p) => p.address.toLowerCase().contains(low) || p.type.title.toLowerCase().contains(low)).take(6).toList();
    });
    _wait?.cancel();
    // search as you type, a moment after the last key
    _wait = Timer(const Duration(milliseconds: 350), () async {
      if (_q.length < 3) return;
      final asked = _q;
      setState(() => _busy = true);
      final r = await searchUs(asked, near: userPos);
      if (mounted && asked == _q) {
        setState(() {
          _results = r;
          _busy = false;
        });
      }
    });
  }

  // Enter: take the first result right away.
  Future<void> _submit(String q) async {
    Store.i.addRecent(q.trim());
    if (_ours.isNotEmpty) {
      Navigator.pop(context, _ours.first);
      return;
    }
    var r = _results;
    if (r.isEmpty) {
      setState(() => _busy = true);
      r = await searchUs(q, near: userPos);
      if (!mounted) return;
      setState(() => _busy = false);
    }
    if (r.isNotEmpty && mounted) Navigator.pop(context, r.first);
  }

  @override
  Widget build(BuildContext context) {
    final store = Store.i;
    final saved = store.savedPlaceData.values.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          autofocus: true,
          onChanged: _changed,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: 'Address, place or city in the US',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            filled: true,
            fillColor: AppColors.paper,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
          child: ListView(shrinkWrap: true, children: [
            if (_q.isEmpty) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in kFilterChips)
                  ActionChip(label: Text(c.$1), onPressed: () => Navigator.pop(context, c.$1)),
              ]),
              if (store.recentSearches.isNotEmpty) _head('Recent'),
              for (final r in store.recentSearches)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(r),
                  onTap: () => _changed(r),
                ),
              if (saved.isNotEmpty) _head('Saved places'),
              for (final p in saved)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.favorite, color: AppColors.red),
                  title: Text(p.address),
                  subtitle: Text(p.type.title),
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
            if (_ours.isNotEmpty) _head('Our places'),
            for (final p in _ours)
              ListTile(
                leading: Glyph(p.type, size: 22, color: colorsFor(p.shownStatus).dark),
                title: Text(p.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p.type.title} · ${p.distance}'),
                onTap: () {
                  store.addRecent(_q);
                  Navigator.pop(context, p);
                },
              ),
            if (_results.isNotEmpty) _head('Addresses'),
            for (final r in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${fmtDistance(const Distance()(userPos, r.pos))} · ${r.subtitle}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  store.addRecent(_q);
                  Navigator.pop(context, r);
                },
              ),
          ]),
        ),
        const Text('Search © OpenStreetMap Nominatim', style: TextStyle(fontSize: 10, color: AppColors.soft)),
      ]),
    );
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.soft)),
      );
}
