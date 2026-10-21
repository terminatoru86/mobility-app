import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_state.dart';
import '../data/location.dart';
import '../data/osm.dart';
import '../data/routing.dart';
import '../data/places.dart';
import '../theme.dart';
import '../widgets/cluster.dart';
import '../widgets/directions.dart';
import '../widgets/guide.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart';
import '../widgets/signup.dart';
import '../widgets/tiles.dart';

class MapScreen extends StatefulWidget {
  final AppState state;
  final GlobalKey navKey;
  const MapScreen({super.key, required this.state, required this.navKey});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  double _zoom = 15;
  String? _filter;
  String? _selected;
  bool _showGuide = false;
  bool _weatherFace = false;
  Timer? _flip;
  Timer? _pinClock;
  Timer? _debounce;
  final _osm = OsmService();
  bool _loading = false;

  // Trip: route from the rider to the chosen place
  Place? _tripTo;
  RouteResult? _route;
  bool _routing = false;

  final _kSearch = GlobalKey();
  final _kFilters = GlobalKey();
  final _kPins = GlobalKey();
  final _kLocate = GlobalKey();
  final _kReport = GlobalKey();
  final _kSos = GlobalKey();

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _flip?.cancel();
    _pinClock?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  /// Real places from OpenStreetMap; the demo places only until those arrive.
  List<Place> get _all => _osm.places.isEmpty ? demoPlaces : _osm.places.values.toList();

  List<Place> get _visible {
    final all = _all;
    return _filter == null ? all : all.where((p) => p.type.group == _filter).toList();
  }

  /// GPS: move the map to the rider. Without GPS the map stays where it is.
  Future<void> _locate() async {
    final pos = await currentPosition();
    if (!mounted) return;
    if (pos == null) {
      _map.move(userPos, 15);
      return;
    }
    userPos = pos;
    _osm.refreshDistances();
    setState(() {});
    _map.move(pos, 15);
  }

  /// Trip button: bike route from where you are to the place, drawn in blue.
  Future<void> _trip(Place p) async {
    setState(() {
      _tripTo = p;
      _route = null;
      _routing = true;
    });
    final r = await bikeRoute([userPos, p.pos]);
    if (!mounted || _tripTo != p) return;
    setState(() {
      _route = r;
      _routing = false;
    });
    if (r != null && r.points.length > 1) {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(r.points),
        padding: const EdgeInsets.fromLTRB(40, 160, 40, 200),
      ));
    }
  }

  /// Search any address or city in the US and jump there.
  Future<void> _openSearch() async {
    final picked = await showModalBottomSheet<GeoResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _SearchSheet(),
    );
    if (picked != null && mounted) _map.move(picked.pos, 15);
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

  Future<void> _openPlace(Place p) async {
    setState(() => _selected = p.id);
    if (p.type == PlaceType.sharing && !widget.state.sharingChosen) {
      await _chooseOperators();
      if (!mounted) return;
    }
    await showPlaceSheet(
      context,
      p,
      myVehicle: widget.state.myVehicle,
      showVehicleTip: !widget.state.sheetTipDone,
      onTipSeen: widget.state.setSheetTipDone,
      onTrip: () => _trip(p),
    );
    if (mounted) setState(() => _selected = null);
  }

  // First tap on a sharing pin: pick the operators to show (filtered by GPS).
  Future<void> _chooseOperators() async {
    final chosen = {for (final o in demoOperators) o.name: o.inArea};
    String priceFilter = 'All';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
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
            for (final o in demoOperators)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: chosen[o.name],
                onChanged: (v) => set(() => chosen[o.name] = v ?? false),
                title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                subtitle: Text(o.price, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const Center(
              child: Text('All operators in the US (70+) ›',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Done · ${chosen.values.where((v) => v).length} operators'),
            ),
          ]),
        ),
      ),
    );
    await widget.state.setSharingChosen();
  }

  List<Marker> _markers() {
    final pins = _visible;
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

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
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
          // OpenStreetMap basemap
          baseTiles(),
          if (_route != null) routeLayer(_route!.points),
          MarkerLayer(markers: [
            Marker(point: userPos, width: 34, height: 34, child: const UserDot()),
            ..._markers(),
          ]),
        ],
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
          if (_loading)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 6),
                Text('Loading places…', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            )
          else if (_osm.lastError != null)
            GestureDetector(
              onTap: _loadVisible,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.redTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.red),
                ),
                child: Text('Places not loaded: ${_osm.lastError} · tap to retry',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.redDark)),
              ),
            ),
        ]),
      ),
      Positioned(
        right: 14,
        bottom: _tripTo != null ? 110 : 24,
        child: Column(children: [
          _roundBtn(_kLocate, Icons.my_location, Colors.white, AppColors.ink, _locate),
          const SizedBox(height: 12),
          _roundBtn(_kReport, Icons.add, AppColors.primary, Colors.white, () {}),
        ]),
      ),
      Positioned(
        left: 14,
        bottom: _tripTo != null ? 116 : 30,
        child: GestureDetector(
          key: _kSos,
          onLongPress: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [BoxShadow(color: Color(0x40E0484D), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),
        ),
      ),
      const Positioned(
        right: 4,
        bottom: 2,
        child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9, color: AppColors.soft)),
      ),
      if (_tripTo != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 18,
          child: RoutePanel(
            title: _tripTo!.address,
            route: _route,
            loading: _routing,
            failed: !_routing && _route == null,
            onRetry: () => _trip(_tripTo!),
            onGo: () => showDirections(context, _route!, _tripTo!.address),
            onClose: () => setState(() {
              _tripTo = null;
              _route = null;
            }),
          ),
        ),
      if (_showGuide)
        Positioned.fill(
          child: GuideOverlay(
            total: 8,
            steps: [
              GuideStep(_kSearch, 'Search, vehicle and weather',
                  'Type an address or a place. The circle on the left turns: once your vehicle, once the weather.'),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Container(
              key: ValueKey(_weatherFace),
              width: 64,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: AppColors.slate, width: 1.5),
              ),
              alignment: Alignment.center,
              child: _weatherFace
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.wb_cloudy_outlined, size: 18),
                      SizedBox(width: 3),
                      Text('21°', style: TextStyle(fontWeight: FontWeight.w800)),
                    ])
                  : Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset((widget.state.myVehicle ?? Vehicle.bike).asset),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Search address or city', style: TextStyle(color: AppColors.soft, fontSize: 16))),
        ]),
      ));

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

  Widget _roundBtn(Key key, IconData i, Color bg, Color fg, VoidCallback onTap) => Material(
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

  // Used so the import of latlong2 stays explicit for readers.
  LatLng get center => _map.camera.center;
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  Timer? _wait;
  List<GeoResult> _results = [];
  bool _busy = false;

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _wait?.cancel();
    // the free OpenStreetMap search allows about one request per second
    _wait = Timer(const Duration(milliseconds: 800), () async {
      setState(() => _busy = true);
      final r = await searchUs(q);
      if (mounted) {
        setState(() {
          _results = r;
          _busy = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          autofocus: true,
          onChanged: _changed,
          decoration: InputDecoration(
            hintText: 'Address or city in the US',
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
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: ListView(shrinkWrap: true, children: [
            for (final r in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, r),
              ),
          ]),
        ),
        const Text('Search © OpenStreetMap Nominatim', style: TextStyle(fontSize: 10, color: AppColors.soft)),
      ]),
    );
  }
}
