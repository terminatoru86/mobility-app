import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_state.dart';
import '../data/location.dart';
import '../data/osm.dart';
import '../data/places.dart';
import '../data/store.dart';
import '../data/weather.dart';
import '../theme.dart';
import '../widgets/cluster.dart';
import '../widgets/guide.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart';
import '../widgets/signup.dart';
import '../widgets/tiles.dart';
import 'map_extras.dart';
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
  Timer? _debounce;
  Timer? _sosHold;
  double _sosProgress = 0;
  final _osm = OsmService();
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
    _pinClock = Timer.periodic(const Duration(seconds: 4), (_) => pinShowsAge.value = !pinShowsAge.value);
    // real places: the cities shipped with the app and the ones saved on the phone (instant),
    // then the visible area from OpenStreetMap
    _osm.loadBundled().then((_) => _osm.loadCache()).then((_) {
      if (mounted) setState(() {});
      _loadVisible();
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Store.i.removeListener(_storeChanged);
    _flip?.cancel();
    _pinClock?.cancel();
    _debounce?.cancel();
    _sosHold?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    final w = await fetchWeather(userPos);
    if (mounted && w != null) setState(() => _wx = w);
  }

  /// Real places (OpenStreetMap), with what riders confirmed in Stats; demo places only until they arrive.
  List<Place> get _all {
    final base = _osm.places.isEmpty ? demoPlaces : _osm.places.values;
    final conf = Store.i.confirmations;
    return [
      for (final p in base)
        if (Store.i.showOnMap[p.type] ?? true)
          conf.containsKey(p.id) ? p.withStatus(conf[p.id]!.status, '<5 min') : p,
    ];
  }

  List<Place> get _visible {
    final all = _all;
    return _filter == null ? all : all.where((p) => p.type.group == _filter).toList();
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
      _map.move(userPos, 15);
      return;
    }
    userPos = pos;
    _osm.refreshDistances();
    setState(() => _noGps = false);
    _map.move(pos, 15);
    _loadWeather();
  }

  /// Trip: choose the route, then GO for the GPS guidance.
  Future<void> _trip(Place p) async {
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

  // ── Parking near a searched address ──
  static const _walk = Distance();

  void _showDestination(GeoResult g) {
    if (!Store.i.parkNearDest) {
      setState(() => _dest = null);
      _map.move(g.pos, 16);
      return;
    }
    setState(() => _dest = g);
    _map.move(g.pos, 16.3);
  }

  void _clearDestination() => setState(() => _dest = null);

  /// Parking within 500 m of the address (1 km if there is none), nearest first.
  (List<Place>, double) _destParking() {
    final d = _dest;
    if (d == null) return (const [], 0);
    final parking = _all.where((p) => p.type.group == 'Parking').toList();
    for (final radius in const [500.0, 1000.0]) {
      final near = parking.where((p) => _walk(d.pos, p.pos) <= radius).toList()
        ..sort((a, b) => _walk(d.pos, a.pos).compareTo(_walk(d.pos, b.pos)));
      if (near.isNotEmpty) return (near, radius);
    }
    return (const [], 1000);
  }

  Widget _destCard(List<Place> list, double radius) {
    final d = _dest!;
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_parking, color: AppColors.primary, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Parking near ${d.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            TextButton.icon(
              onPressed: () => _trip(Place(
                id: 'dest',
                type: PlaceType.shop,
                address: d.title,
                pos: d.pos,
                status: Status.neutral,
                distance: '',
                etaMin: const {},
              )),
              icon: const Icon(Icons.navigation_rounded, size: 16),
              label: const Text('Trip'),
            ),
            IconButton(onPressed: _clearDestination, icon: const Icon(Icons.close), tooltip: 'Hide'),
          ]),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 4, 8, 4),
              child: Text('No bike parking known within 1 km. Loading the area… or report a new place with +.',
                  style: TextStyle(color: AppColors.soft)),
            )
          else ...[
            Text('${list.length} within ${radius.round()} m · nearest first',
                style: const TextStyle(fontSize: 12, color: AppColors.soft)),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in list.take(12)) _destTile(p),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _destTile(Place p) {
    final c = colorsFor(p.shownStatus);
    final m = _walk(_dest!.pos, p.pos);
    return GestureDetector(
      onTap: () => _openPlace(p),
      child: Container(
        width: 190,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.tint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.main, width: 1.5),
        ),
        child: Row(children: [
          Glyph(p.type, size: 26, color: c.dark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                p.shownStatus == Status.full ? 'full · ${p.age}' : '${p.count ?? '—'} free · ${p.age.isEmpty ? 'no data' : p.age}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.dark),
              ),
              Text('${m.round()} m · ${(m / 80).ceil()} min walk', style: const TextStyle(fontSize: 11, color: AppColors.soft)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _loadVisible() async {
    if (!mounted || _loading) return;
    MapCamera? cam;
    try {
      cam = _map.camera;
    } catch (_) {
      cam = null; // map not ready yet
    }
    if (cam == null) return;
    if (cam.zoom < 12) return; // too far out: we show what we already have
    final b = cam.visibleBounds;
    setState(() => _loading = true);
    final changed = await _osm.loadArea(b.south, b.west, b.north, b.east);
    if (!mounted) return;
    setState(() => _loading = false);
    if (changed) setState(() {});
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

  List<Marker> _markers() {
    final pins = _dest != null ? _destParking().$1 : _visible;
    if (_zoom < 15) {
      return clusterPlaces(pins, _zoom).map((c) {
        if (c.places.length == 1) return _pinMarker(c.places.first);
        return Marker(
          point: c.center,
          width: 48,
          height: 48,
          child: GestureDetector(
            onTap: () => _map.move(c.center, 15),
            child: ClusterBadge(cluster: c),
          ),
        );
      }).toList();
    }
    return pins.map(_pinMarker).toList();
  }

  Marker _pinMarker(Place p) => Marker(
        point: p.pos,
        width: PlacePin.width,
        height: PlacePin.height,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _openPlace(p),
          child: PlacePin(place: p, selected: _selected == p.id, small: _zoom < 16),
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
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: userPos,
          initialZoom: 15,
          minZoom: 3,
          maxZoom: 19,
          onPositionChanged: (camera, hasGesture) {
            // rebuild the pins only when the zoom crosses a half step, not on every frame
            final bucket = (camera.zoom * 2).floor() / 2;
            if (bucket != _zoom) setState(() => _zoom = bucket);
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 700), _loadVisible);
          },
        ),
        children: [
          if (store.satellite) satelliteTiles() else baseTiles(),
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
          if (_dest != null)
            CircleLayer(circles: [
              CircleMarker(
                point: _dest!.pos,
                radius: _destParking().$2,
                useRadiusInMeter: true,
                color: AppColors.blue.withValues(alpha: 0.07),
                borderColor: AppColors.blue,
                borderStrokeWidth: 1.5,
              ),
            ]),
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
              _pill(Icons.location_disabled, 'Turn on location', Colors.white, AppColors.ink, _locate),
          ]),
        ]),
      ),
      if (_dest != null && !_list)
        Positioned(
          left: 10,
          right: 10,
          bottom: 14,
          child: Builder(builder: (_) {
            final (list, radius) = _destParking();
            return _destCard(list, radius);
          }),
        ),
      if (!_list)
        Positioned(
          right: 14,
          bottom: _dest != null ? 170 : 24,
          child: Column(children: [
            GestureDetector(
              key: _kLocate,
              onDoubleTap: () => store.setSatellite(!store.satellite),
              child: _roundBtn(Icons.my_location, Colors.white, AppColors.ink, _locate),
            ),
            const SizedBox(height: 12),
            _roundBtn(Icons.add, AppColors.primary, Colors.white, () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportMenu(pos: userPos)));
            }, key: _kReport),
          ]),
        ),
      Positioned(left: 14, bottom: _dest != null ? 176 : 30, child: _sosButton()),
      const Positioned(
        right: 4,
        bottom: 2,
        child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9, color: AppColors.soft)),
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
              GuideStep(_kLocate, 'Where you are', 'One tap brings you back. Two taps switch between map and satellite.'),
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
      child: Stack(alignment: Alignment.center, children: [
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
              onTap: () {
                if (_wx != null) {
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
          for (final f in const [
            ('Parking', PlaceType.parkOutdoor),
            ('Charging', PlaceType.charging),
            ('Service', PlaceType.service),
            ('Shop', PlaceType.shop),
            ('Sharing', PlaceType.sharing),
          ])
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
                    Glyph(f.$2, size: 16, color: AppColors.primary),
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
                for (final c in const ['Parking', 'Charging', 'Service', 'Shop', 'Sharing'])
                  ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c)),
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
                subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
