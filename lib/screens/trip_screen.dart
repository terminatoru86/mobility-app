import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/routing.dart';
import '../data/store.dart';
import '../data/weather.dart';
import '../theme.dart';
import '../widgets/directions.dart';
import '../widgets/pin.dart';
import '../widgets/sheet_parts.dart';
import '../widgets/tiles.dart';

/// Trip → choose the route (Fast / Balanced / Quiet) → GO → GPS guidance → Stats.
Future<void> startTrip(
  BuildContext context, {
  required LatLng to,
  required String toName,
  Place? place,
  List<Place> nearby = const [],
  Vehicle? myVehicle,
}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutePlanner(to: to, toName: toName, place: place, nearby: nearby, myVehicle: myVehicle),
    ));

// ───────────────────────── 3.5 Choose the route, before GO ─────────────────────────

class RoutePlanner extends StatefulWidget {
  final LatLng to;
  final String toName;
  final Place? place;
  final List<Place> nearby;
  final Vehicle? myVehicle;
  const RoutePlanner(
      {super.key, required this.to, required this.toName, this.place, this.nearby = const [], this.myVehicle});

  @override
  State<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends State<RoutePlanner> {
  final _map = MapController();
  late LatLng _from = userPos;
  late LatLng _to = widget.to;
  String _fromName = 'My location';
  late String _toName = widget.toName;
  List<RouteResult> _routes = [];
  int _sel = 0;
  bool _loading = true;
  bool _ready = false;
  Weather? _wx;
  // Destination is an address (not one of our parking places): suggest a rack 300 m or closer.
  Place? _rack;
  List<LatLng> _walk = const [];

  @override
  void initState() {
    super.initState();
    _findRack();
    _calc();
    fetchWeather(userPos).then((w) {
      if (mounted) setState(() => _wx = w);
    });
  }

  Future<void> _findRack() async {
    final p = widget.place;
    if (p != null && p.type.group == 'Parking') {
      _rack = null;
      _walk = const [];
      return;
    }
    final rack = parkingNear(_to);
    _rack = rack;
    _walk = rack == null ? const [] : [_to, rack.pos];
    if (rack != null) {
      final w = await footPath(_to, rack.pos);
      if (mounted && _rack == rack) setState(() => _walk = w);
    }
  }

  Future<void> _calc() async {
    setState(() => _loading = true);
    final r = await bikeRoutes([_from, _to]);
    if (!mounted) return;
    setState(() {
      _routes = r;
      _sel = 0;
      _loading = false;
    });
    _fit();
  }

  void _fit() {
    if (!_ready || _routes.isEmpty) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(_routes[_sel].points),
      padding: const EdgeInsets.all(30),
    ));
  }

  void _swap() {
    setState(() {
      final p = _from;
      _from = _to;
      _to = p;
      final n = _fromName;
      _fromName = _toName;
      _toName = n;
    });
    _calc();
  }

  RouteResult? get _r => _routes.isEmpty ? null : _routes[_sel.clamp(0, _routes.length - 1)];

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: Colors.white, title: const Text('Choose the route')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 110), children: [
        // Start / End
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(
              child: Column(children: [
                _endRow(Icons.my_location, AppColors.blue, 'Start', _fromName),
                const Divider(height: 10),
                _endRow(Icons.place, AppColors.red, 'End', _toName),
              ]),
            ),
            IconButton(onPressed: _swap, icon: const Icon(Icons.swap_vert)),
          ]),
        ),
        const SizedBox(height: 10),
        if (_wx != null && r != null) _windChip(r),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _to,
                initialZoom: 13,
                onMapReady: () {
                  _ready = true;
                  _fit();
                },
              ),
              children: [
                baseTiles(),
                PolylineLayer(polylines: [
                  for (int i = 0; i < _routes.length; i++)
                    if (i != _sel)
                      Polyline(points: _routes[i].points, strokeWidth: 5, color: const Color(0xFF9DB6E8)),
                ]),
                if (r != null) routeLayer(r.points),
                if (_walk.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: _walk,
                      strokeWidth: 5,
                      color: AppColors.blue,
                      pattern: const StrokePattern.dotted(spacingFactor: 2),
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (_rack != null)
                    Marker(
                      point: _rack!.pos,
                      width: PlacePin.width,
                      height: PlacePin.height,
                      alignment: Alignment.topCenter,
                      child: PlacePin(place: _rack!, small: true),
                    ),
                  Marker(point: _from, width: 34, height: 34, child: const UserDot()),
                  Marker(
                    point: _to,
                    width: 30,
                    height: 30,
                    child: const Icon(Icons.flag_rounded, color: AppColors.red, size: 30),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (r == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              const Text('No bike route found right now.', style: TextStyle(fontWeight: FontWeight.w800)),
              TextButton(onPressed: _calc, child: const Text('Try again')),
            ]),
          )
        else ...[
          // Fast / Balanced / Quiet
          Row(children: [
            for (final label in const ['Fast', 'Balanced', 'Quiet'])
              Expanded(child: _modeTile(label)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: VehicleTile(
                place: _tripPlace(r),
                myVehicle: widget.myVehicle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FactTile(r.distance, 'distance')),
          ]),
          const SizedBox(height: 4),
          Text('↗ ${r.climb} m climb · ↘ ${(r.climb * 0.9).round()} m descent',
              style: const TextStyle(fontSize: 12, color: AppColors.soft, fontWeight: FontWeight.w600)),
          if (_rack != null) ...[
            const SizedBox(height: 10),
            _rackSuggestion(),
          ],
          const SizedBox(height: 12),
          _safety(r),
        ],
      ]),
      bottomSheet: r == null
          ? null
          : Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  OutlinedButton(
                    onPressed: () => _moreInfo(r),
                    style: OutlinedButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 48)),
                    child: const Text('More info'),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () {
                      Store.i.saveRoute(SavedRoute('$_fromName → $_toName', _from, _to, r.meters, r.seconds));
                      setState(() {});
                    },
                    icon: Icon(
                      Store.i.savedRoutes.any((s) => s.name == '$_fromName → $_toName')
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => GuidanceScreen(
                          route: r,
                          to: _to,
                          toName: _toName,
                          place: widget.place,
                          nearby: widget.nearby,
                          suggestRack: _rack,
                        ),
                      )),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
                      child: const Text('GO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _rackSuggestion() {
    final rack = _rack!;
    final m = const Distance()(_to, rack.pos);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.blue, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Glyph(rack.type, size: 22, color: colorsFor(rack.shownStatus).dark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${rack.type.title} ${m.round()} m from your destination · ${(m / 80).ceil()} min walk',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Suggestion only: the GPS still takes you to the address. We show the walk again when you arrive.',
            style: TextStyle(fontSize: 12, color: AppColors.soft)),
      ]),
    );
  }

  Place _tripPlace(RouteResult r) => Place(
        id: 'trip',
        type: PlaceType.rack,
        address: '',
        pos: _to,
        status: Status.free,
        distance: r.distance,
        accepts: const [Vehicle.bike, Vehicle.ebike, Vehicle.scooter, Vehicle.moped],
        etaMin: {
          Vehicle.bike: (r.seconds / 60).round(),
          Vehicle.ebike: (secondsFor(r.meters, 'ebike') / 60).round(),
          Vehicle.scooter: (secondsFor(r.meters, 'scooter') / 60).round(),
          Vehicle.moped: (secondsFor(r.meters, 'moped') / 60).round(),
        },
      );

  Widget _endRow(IconData i, Color c, String label, String text) => Row(children: [
        Icon(i, color: c, size: 18),
        const SizedBox(width: 8),
        SizedBox(width: 40, child: Text(label, style: const TextStyle(color: AppColors.soft, fontSize: 12))),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]);

  Widget _modeTile(String label) {
    final i = _routes.indexWhere((x) => x.label == label);
    final on = i == _sel && i >= 0;
    final x = i >= 0 ? _routes[i] : null;
    return GestureDetector(
      onTap: x == null
          ? null
          : () {
              setState(() => _sel = i);
              _fit();
            },
      child: Opacity(
        opacity: x == null ? 0.4 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE6EEFB) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? AppColors.blue : AppColors.line, width: on ? 2 : 1),
          ),
          child: Column(children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: on ? AppColors.blue : AppColors.ink)),
            Text(x == null ? '—' : x.duration, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(x == null ? 'not available' : 'arrive ${x.arrival}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.soft)),
          ]),
        ),
      ),
    );
  }

  // Share of each kind of road, guessed from the street names on the route.
  Map<String, double> _roadMix(RouteResult r) {
    final m = {'Protected lanes': 0.0, 'Quiet streets': 0.0, 'Bike lanes': 0.0, 'Shared roads': 0.0, 'Main roads': 0.0};
    for (final s in r.steps) {
      final n = s.street.toLowerCase();
      final k = (n.contains('trail') || n.contains('path') || n.contains('greenway') || n.contains('riverwalk'))
          ? 'Protected lanes'
          : (n.contains('dr') || n.contains('blvd') || n.contains('ave') && n.contains('lake shore'))
              ? 'Main roads'
              : (n.contains('ave') || n.contains('rd'))
                  ? 'Bike lanes'
                  : n.isEmpty
                      ? 'Shared roads'
                      : 'Quiet streets';
      m[k] = m[k]! + s.meters;
    }
    final total = m.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return m;
    return {for (final e in m.entries) e.key: e.value / total};
  }

  Widget _safety(RouteResult r) {
    final mix = _roadMix(r);
    const colors = {
      'Protected lanes': AppColors.green,
      'Quiet streets': Color(0xFF8CC063),
      'Bike lanes': AppColors.yellow,
      'Shared roads': Color(0xFFF08A3C),
      'Main roads': AppColors.red,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        for (final e in mix.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 110, child: Text(e.key, style: const TextStyle(fontSize: 12))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.value,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE3E8EA),
                    color: colors[e.key],
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${(e.value * 100).round()}%',
                    textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _windChip(RouteResult r) {
    final w = _wx!;
    final dir = bearing(r.points.first, r.points.last);
    // wind blows FROM windDir; riding towards dir: head wind if they point the same way
    final diff = ((w.windDir - dir + 540) % 360) - 180;
    final head = diff.abs() < 60;
    final tail = diff.abs() > 120;
    final txt = head ? 'Head wind' : (tail ? 'Tail wind' : 'Side wind');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: head ? AppColors.yellowTint : AppColors.greenTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$txt · ${w.wind.round()} km/h from ${w.windFrom} · ${w.temp.round()}° ${w.sky}',
          style: TextStyle(fontWeight: FontWeight.w800, color: head ? AppColors.yellowDark : AppColors.greenDark)),
    );
  }

  void _moreInfo(RouteResult r) {
    final mix = _roadMix(r);
    final lights = r.steps.where((s) => s.text.startsWith('Turn')).length;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('More info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text('$_fromName → $_toName', style: const TextStyle(color: AppColors.soft)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FactTile(r.distance, 'distance')),
            const SizedBox(width: 6),
            Expanded(child: FactTile('${r.climb} m', 'climb')),
            const SizedBox(width: 6),
            Expanded(child: FactTile(r.duration, 'duration')),
          ]),
          const SizedBox(height: 12),
          Text('■ ${(100 - (mix['Shared roads']! * 30)).round()}% paved · ▨ ${(mix['Shared roads']! * 30).round()}% unpaved',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('On the route: 🚦 about $lights traffic lights · ⛔ ${math.max(0, lights ~/ 3)} stops',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Road types are estimated from street names until our map data covers them.',
              style: TextStyle(fontSize: 11, color: AppColors.soft)),
        ]),
      ),
    );
  }
}

// ───────────────────────── 3.5 GPS guidance ─────────────────────────

class GuidanceScreen extends StatefulWidget {
  final RouteResult route;
  final LatLng to;
  final String toName;
  final Place? place;
  final List<Place> nearby;
  final Place? suggestRack; // a rack near an address destination (shown again on arrival)
  const GuidanceScreen({
    super.key,
    required this.route,
    required this.to,
    required this.toName,
    this.place,
    this.nearby = const [],
    this.suggestRack,
  });

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  final _map = MapController();
  late RouteResult _route = widget.route;
  late LatLng _to = widget.to;
  late String _toName = widget.toName;
  late Place? _place = widget.place;
  List<LatLng> _walk = const []; // dotted walking line to the suggested rack
  bool _showRackCard = false;
  static const _zoom = 18.4; // close to the street, but not all the way in
  late LatLng _pos = userPos;
  double _heading = 0;
  double _speed = 0; // km/h
  double _along = 0; // metres done on the current route
  double _ridden = 0; // metres ridden in total
  int _offCount = 0;
  bool _recalc = false;
  bool _follow = true;
  bool _simulating = false;
  bool _arrived = false;
  final _start = DateTime.now();
  StreamSubscription<Position>? _gps;
  Timer? _sim;
  Timer? _clock;
  LatLng? _last;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _startGps();
    final rack = widget.suggestRack;
    if (rack != null) {
      _walk = [widget.to, rack.pos];
      footPath(widget.to, rack.pos).then((w) {
        if (mounted) setState(() => _walk = w);
      });
    }
    // On a computer the position does not move: start the ride simulator so the guidance can be tried.
    if (kIsWeb) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && !_simulating && _ridden == 0) _toggleSim();
      });
    }
  }

  void _startGps() {
    try {
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
      ).listen((p) {
        if (_simulating) return;
        _onPosition(LatLng(p.latitude, p.longitude), p.speed * 3.6, p.heading);
      }, onError: (_) {});
    } catch (_) {}
  }

  void _toggleSim() {
    if (_simulating) {
      _sim?.cancel();
      setState(() => _simulating = false);
      return;
    }
    setState(() => _simulating = true);
    var m = _along;
    _sim = Timer.periodic(const Duration(milliseconds: 500), (_) {
      m += 18 / 3.6 * 0.5 * 4; // 18 km/h, 4x faster than real life
      final p = pointAlong(_route.points, m);
      final ahead = pointAlong(_route.points, m + 10);
      _onPosition(p, 18, bearing(p, ahead));
    });
  }

  void _onPosition(LatLng p, double kmh, double heading) {
    if (!mounted || _arrived) return;
    if (_last != null) _ridden += const Distance()(_last!, p);
    _last = p;
    final (off, along) = projectOnRoute(p, _route.points);
    setState(() {
      _pos = p;
      userPos = p;
      _speed = kmh.isNaN || kmh < 0 ? 0 : kmh;
      if (!heading.isNaN && heading != 0) _heading = heading;
      _along = along;
    });
    if (_follow) {
      try {
        _map.move(p, math.max(_map.camera.zoom, _zoom));
      } catch (_) {}
    }

    final remaining = _route.meters - along;
    if (remaining < 25 || const Distance()(p, _to) < 25) {
      _arrive();
      return;
    }
    // off the route for a while: calculate again from here
    if (off > 45) {
      _offCount++;
      if (_offCount >= 3 && !_recalc) _recalculate();
    } else {
      _offCount = 0;
    }
  }

  Future<void> _recalculate() async {
    setState(() => _recalc = true);
    final r = await bikeRoute([_pos, _to]);
    if (!mounted) return;
    setState(() {
      if (r != null) {
        _route = r;
        _along = 0;
      }
      _recalc = false;
      _offCount = 0;
    });
  }

  Future<void> _arrive() async {
    if (_arrived) return;
    _arrived = true;
    _sim?.cancel();
    _simulating = false;
    await _gps?.cancel();
    if (!mounted) return;

    // 1) Arrived at one of our places (or right next to one): confirm its status with the 3 colours.
    var stats = (_place != null && !_place!.type.isNeutral) ? _place : null;
    stats ??= _nearestOurs(_pos, 40);
    if (stats != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(place: stats!)));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // 2) Arrived at an address with a rack nearby: show the dotted walk again, like a walking route.
    if (widget.suggestRack != null && _place == null) {
      setState(() => _showRackCard = true);
      try {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([_pos, ..._walk]),
          padding: const EdgeInsets.fromLTRB(60, 180, 60, 260),
          maxZoom: 18.5,
        ));
      } catch (_) {}
      return;
    }

    // 3) Anything else.
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('You have arrived'),
        content: Text(_toName),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Place? _nearestOurs(LatLng at, double max) {
    const d = Distance();
    Place? best;
    var bestM = max;
    for (final p in [...widget.nearby, ...knownPlaces]) {
      if (p.type.isNeutral) continue;
      final m = d(at, p.pos);
      if (m <= bestM) {
        bestM = m;
        best = p;
      }
    }
    return best;
  }

  // From the address, ride the last metres to the suggested rack (Stats appear there).
  Future<void> _rideToRack() async {
    final rack = widget.suggestRack!;
    final r = await bikeRoute([_pos, rack.pos]);
    if (!mounted) return;
    setState(() {
      _showRackCard = false;
      _place = rack;
      _to = rack.pos;
      _toName = rack.address;
      if (r != null) _route = r;
      _along = 0;
      _arrived = false;
      _follow = true;
    });
    _startGps();
    if (kIsWeb) _toggleSim();
  }

  Widget _rackCard() {
    final rack = widget.suggestRack!;
    final m = const Distance()(_pos, rack.pos);
    return Material(
      color: Colors.white,
      elevation: 10,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('You have arrived · $_toName',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          Row(children: [
            Glyph(rack.type, size: 24, color: colorsFor(rack.shownStatus).dark),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${rack.type.title} ${m.round()} m away · ${(m / 80).ceil()} min walk',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Follow the dotted line to leave your bike there.', style: TextStyle(fontSize: 12, color: AppColors.soft)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), shape: const StadiumBorder()),
                child: const Text('Done'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _rideToRack,
                style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
                child: const Text('Go to the rack'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _gps?.cancel();
    _sim?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  // the next maneuver after the current position
  (RouteStep, double, RouteStep?) _next() {
    final steps = _route.steps;
    if (steps.isEmpty) return (RouteStep('Ride to $_toName', '', 0, _to), math.max(0.0, _route.meters - _along), null);
    for (int i = 0; i < steps.length; i++) {
      final (_, at) = projectOnRoute(steps[i].at, _route.points);
      if (at > _along + 5) {
        return (steps[i], at - _along, i + 1 < steps.length ? steps[i + 1] : null);
      }
    }
    return (steps.last, math.max(0.0, _route.meters - _along), null);
  }

  @override
  Widget build(BuildContext context) {
    final (step, dist, then) = _next();
    final remaining = math.max(0.0, _route.meters - _along);
    final secLeft = remaining / 1000 / 15 * 3600;
    final elapsed = DateTime.now().difference(_start);
    final done = pointsUpTo(_route.points, _along);
    final hazards = Store.i.reports.where((r) => r.onMap).toList();
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _pos,
            initialZoom: _zoom,
            onPositionChanged: (_, gesture) {
              if (gesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            baseTiles(),
            routeLayer(_route.points),
            if (done.length > 1)
              PolylineLayer(polylines: [Polyline(points: done, strokeWidth: 6, color: const Color(0xFF9AA6AC))]),
            if (_walk.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: _walk,
                  strokeWidth: 5,
                  color: AppColors.blue,
                  pattern: const StrokePattern.dotted(spacingFactor: 2),
                ),
              ]),
            MarkerLayer(markers: [
              for (final p in widget.nearby)
                Marker(
                  point: p.pos,
                  width: PlacePin.width,
                  height: PlacePin.height,
                  alignment: Alignment.topCenter,
                  child: PlacePin(place: p, small: true),
                ),
              for (final h in hazards)
                Marker(
                  point: h.pos,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                    child: Icon(h.icon, size: 18, color: AppColors.ink),
                  ),
                ),
              if (widget.suggestRack != null && !widget.nearby.contains(widget.suggestRack))
                Marker(
                  point: widget.suggestRack!.pos,
                  width: PlacePin.width,
                  height: PlacePin.height,
                  alignment: Alignment.topCenter,
                  child: PlacePin(place: widget.suggestRack!, selected: _showRackCard),
                ),
              Marker(
                point: _to,
                width: 34,
                height: 34,
                child: const Icon(Icons.flag_rounded, color: AppColors.red, size: 32),
              ),
              Marker(
                point: _pos,
                width: 46,
                height: 46,
                child: Transform.rotate(
                  angle: _heading * math.pi / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
                      border: Border.all(color: AppColors.blue, width: 2),
                    ),
                    child: const Icon(Icons.navigation_rounded, color: AppColors.blue, size: 28),
                  ),
                ),
              ),
            ]),
          ],
        ),
        // turn banner
        Positioned(
          left: 10,
          right: 10,
          top: top + 8,
          child: Column(children: [
            Material(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showDirections(context, _route, _toName),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(children: [
                    Icon(stepIcon(step.text), color: Colors.white, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fmtDistance(dist),
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                        Text(step.street.isEmpty ? step.text : step.street,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ]),
                    ),
                    const Icon(Icons.format_list_bulleted, color: Colors.white),
                  ]),
                ),
              ),
            ),
            if (then != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF1F57B8), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Then ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Icon(stepIcon(then.text), color: Colors.white, size: 16),
                  ]),
                ),
              ),
            if (_recalc)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
                child: const Text('Recalculating…', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        // recording card + recenter + simulate
        Positioned(
          left: 10,
          bottom: 104,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
            ),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: AppColors.red, size: 12),
              const SizedBox(width: 6),
              _val(_speed.toStringAsFixed(1), 'km/h'),
              const SizedBox(width: 12),
              _val('${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}', 'min:sec'),
              const SizedBox(width: 12),
              _val((_ridden / 1000).toStringAsFixed(1), 'km'),
            ]),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 104,
          child: Column(children: [
            FloatingActionButton.small(
              heroTag: 'sim',
              backgroundColor: _simulating ? AppColors.blue : Colors.white,
              foregroundColor: _simulating ? Colors.white : AppColors.ink,
              tooltip: 'Simulate the ride',
              onPressed: _toggleSim,
              child: Icon(_simulating ? Icons.pause : Icons.play_arrow),
            ),
            if (!_follow)
              FloatingActionButton.small(
                heroTag: 'follow',
                backgroundColor: Colors.white,
                onPressed: () {
                  setState(() => _follow = true);
                  _map.move(_pos, _zoom);
                },
                child: const Icon(Icons.navigation_outlined, color: AppColors.blue),
              ),
          ]),
        ),
        // arrival bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 14, 12, 14 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
            ),
            child: Row(children: [
              _val(arrivalAt(secLeft), 'arrival', big: true),
              const SizedBox(width: 16),
              _val(fmtMinutes(secLeft / 60).replaceAll(' min', ''), 'min left', big: true),
              const SizedBox(width: 16),
              _val((remaining / 1000).toStringAsFixed(1), 'km', big: true),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(80, 44)),
                child: const Text('Stop'),
              ),
            ]),
          ),
        ),
        if (_showRackCard)
          Positioned(left: 10, right: 10, bottom: 14, child: SafeArea(top: false, child: _rackCard())),
      ]),
    );
  }

  Widget _val(String v, String l, {bool big = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: big ? 20 : 15)),
        Text(l, style: const TextStyle(fontSize: 10, color: AppColors.soft)),
      ]);
}

/// The part of the route already ridden.
List<LatLng> pointsUpTo(List<LatLng> pts, double meters) {
  if (meters <= 0 || pts.length < 2) return const [];
  final out = <LatLng>[pts.first];
  var acc = 0.0;
  for (int i = 0; i < pts.length - 1; i++) {
    final seg = const Distance()(pts[i], pts[i + 1]);
    if (acc + seg >= meters) {
      out.add(pointAlong(pts, meters));
      return out;
    }
    acc += seg;
    out.add(pts[i + 1]);
  }
  return out;
}

// ───────────────────────── 3.4 Stats, after you arrive ─────────────────────────

class StatsScreen extends StatelessWidget {
  final Place place;
  const StatsScreen({super.key, required this.place});

  @override
  Widget build(BuildContext context) {
    Widget ball(Status s, Color c1, Color c2, Color dd) => GestureDetector(
          onTap: () {
            Store.i.confirm(place.id, s);
            Navigator.of(context).pop();
          },
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: [c1, c2]),
              boxShadow: [
                BoxShadow(color: dd, offset: const Offset(0, 6)),
                const BoxShadow(color: Color(0x40000000), offset: Offset(0, 10), blurRadius: 12),
              ],
            ),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: Text(place.type.title)),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 20),
          Glyph(place.type, size: 56, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(place.address,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            ball(Status.free, const Color(0xFF93C96E), AppColors.green, const Color(0xFF3B7420)),
            ball(Status.almost, const Color(0xFFFFD866), AppColors.yellow, const Color(0xFFB07F00)),
            ball(Status.full, const Color(0xFFFF8A8D), AppColors.red, const Color(0xFFA82328)),
          ]),
          const Spacer(),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Later')),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}
