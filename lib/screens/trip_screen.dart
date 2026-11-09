import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/location.dart';
import '../data/places.dart';
import '../data/routing.dart';
import '../data/store.dart';
import '../data/weather.dart';
import '../theme.dart';
import '../widgets/compass.dart';
import '../widgets/directions.dart';
import '../widgets/pin.dart';
import '../widgets/road_line.dart';
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
  final List<(String, LatLng)> _via = [];
  late Vehicle _rv = widget.myVehicle ?? Vehicle.bike; // the routes are made for this vehicle // stops added with the ≡+ button
  String _variant = 'standard'; // standard / shared / passenger / cargo (chips under the destination card)
  bool _marked = false; // "Bike line": only marked, paved bike ways
  bool _vehiclePicked = false; // the vehicle chips appear only after a vehicle is tapped below
  /// swiped away to the right: hidden until the app starts again
  static bool _chipsAway = false;
  /// "My location" shows as a small pill first, then pulls into the dot
  bool _meOpen = true;
  Timer? _meTimer;
  void _closeMeLater() {
    _meTimer?.cancel();
    _meTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _meOpen = false);
    });
  }
  // Destination is an address (not one of our parking places): suggest a rack 300 m or closer.
  Place? _rack;
  List<LatLng> _walk = const [];

  @override
  void initState() {
    super.initState();
    _findRack();
    _calc();
    _closeMeLater();
  }

  @override
  void dispose() {
    _meTimer?.cancel();
    super.dispose();
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
    final r = await bikeRoutes([_from, for (final v in _via) v.$2, _to],
        vehicle: _rv.name, variant: _variant, markedOnly: _marked && (_bikeLike || !_vehiclePicked));
    if (!mounted) return;
    setState(() {
      _routes = r;
      _sel = 0;
      _loading = false;
    });
    _fit();
    // real climb and road types arrive a moment later
    for (final x in r) {
      Future.wait([addElevation(x), addRoadMix(x)]).then((_) {
        if (mounted && _routes.contains(x)) setState(() {});
      });
    }
  }

  void _fit() {
    if (!_ready || _routes.isEmpty) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(_routes[_sel].points),
      padding: const EdgeInsets.all(30),
    ));
  }

  /// ⇅: the whole trip the other way round (start ↔ destination, stops in reverse order).
  void _swap() {
    setState(() {
      final p = _from;
      _from = _to;
      _to = p;
      final n = _fromName;
      _fromName = _toName;
      _toName = n;
      final rev = _via.reversed.toList();
      _via
        ..clear()
        ..addAll(rev);
    });
    _findRack();
    _calc();
  }

  RouteResult? get _r => _routes.isEmpty ? null : _routes[_sel.clamp(0, _routes.length - 1)];

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // the map fills the screen; the panel sits over its lower part
        Positioned.fill(
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
                  if (i != _sel) Polyline(points: _routes[i].points, strokeWidth: 5, color: const Color(0xFF9DB6E8)),
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
                for (final p in _nearDest)
                  Marker(
                    point: p.pos,
                    width: PlacePin.width,
                    height: PlacePin.height,
                    alignment: Alignment.topCenter,
                    child: PlacePin(place: p, small: true),
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
        // ── glass card on top: thin blue "My location" strip, destination row, + and ⇅ ──
        Positioned(
          left: 10,
          right: 10,
          top: top + 8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _glassTop(),
            const SizedBox(height: 8),
            if (!_chipsAway)
              Dismissible(
                key: const ValueKey('variant-chips'),
                direction: DismissDirection.startToEnd,
                onDismissed: (_) => setState(() => _chipsAway = true),
                child: _variantChips(),
              ),
          ]),
        ),
        // ── panel ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Color(0x24000000), blurRadius: 20, offset: Offset(0, -5))],
            ),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // handle in the middle, thin chevron (cancel) at the right, on the same line
                SizedBox(
                  height: 22,
                  child: Stack(children: [
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFD3DCDD), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: Color(0xFF7C8A91), weight: 300),
                      ),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), children: [
                    if (_loading)
                      const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                    else if (r == null)
                      _softCard(child: Column(children: [
                        const Text('No bike route found right now.', style: TextStyle(fontWeight: FontWeight.w800)),
                        TextButton(onPressed: _calc, child: const Text('Try again')),
                      ]))
                    else ...[
                      // the same vehicle tile as in the place sheets + distance
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          flex: 3,
                          child: VehicleTile(
                            place: _tripPlace(r),
                            myVehicle: widget.myVehicle,
                            // tap a vehicle: the routes are made again for it (moped and motorcycle use roads)
                            onSelected: (v) {
                              if (v == _rv) {
                                if (_oneRoute) {
                                  // an option was chosen and its row went away: tapping the vehicle brings it back
                                  setState(() {
                                    _variant = 'standard';
                                    _marked = false;
                                  });
                                  _calc();
                                } else if (!_vehiclePicked) {
                                  setState(() => _vehiclePicked = true);
                                }
                                return;
                              }
                              setState(() {
                                _vehiclePicked = true;
                                _rv = v;
                                _variant = 'standard';
                                if (!_bikeLike) _marked = false;
                              });
                              _calc();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: FactTile(r.distance, 'distance')),
                      ]),
                      // "Only bike marked": one route on marked bike ways, no Fast/Balanced/Quiet, no summary
                      if (!_oneRoute) ...[const SizedBox(height: 8), _segmented()],
                      const SizedBox(height: 8),
                      _nearCard(r),
                      if (!_oneRoute) ...[const SizedBox(height: 8), _summaryCard(r)],
                    ],
                  ]),
                ),
                if (r != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                    child: Row(children: [
                      _roundBtn(Icons.format_list_bulleted, () => _moreInfo(r)),
                      const SizedBox(width: 8),
                      _cancelButton(),
                      const SizedBox(width: 8),
                      Expanded(child: _goButton(r)),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }


  Widget _softCard({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(12, 9, 10, 10)}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  // ── top card ──
  /// "My location" is only a white dot with blue at the left; the same small dots as the route sign
  /// in the panel join it to the destination flag, like a route. The destination is one thin bar.
  static const _rowH = 38.0, _gap = 12.0;

  Widget _glassTop() {
    // the dot of my location floats above the card, over the map; a "cable" of small dots
    // goes down from it into the card, to the first icon (a stop, or the destination flag)
    const air = 26.0; // space above the card where the dot floats
    final rows = <Widget>[
      for (final (i, v) in _via.indexed) ...[
        _destRow(Icons.circle_outlined, AppColors.soft, v.$1, '', () => _editVia(i), plus: false, small: true),
        const SizedBox(
          width: 22,
          height: _gap,
          child: CustomPaint(painter: _WavyWire(from: Offset(11, -2), to: Offset(11, _gap + 2))),
        ),
      ],
      _destRow(Icons.flag_rounded, AppColors.red, _toName, _toSub, () => _edit(false), plus: _via.isNotEmpty),
    ];
    const cardLeft = 18.0; // narrow lane at the left for the dot and the wire
    const iconX = cardLeft + 6 + 11; // centre of the first icon (stop or flag) in the card
    const iconY = air + 5 + _rowH / 2;
    return Stack(clipBehavior: Clip.none, children: [
      Padding(
        padding: const EdgeInsets.only(top: air, left: cardLeft),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 44, 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.80),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
            ),
          ),
        ),
      ),
      // the wire: it waves down from the dot, blue to red, and turns into the first icon
      const Positioned(
        left: 0,
        top: 0,
        width: iconX,
        height: iconY,
        child: IgnorePointer(
          child: CustomPaint(painter: _WavyWire(from: Offset(7 + 5, 18), to: Offset(iconX - 10, iconY))),
        ),
      ),
      // my location: first a small white pill "My location", which then pulls into the blue dot;
      // the wavy wire joins it to the flag. Tap the dot: the pill opens again; tap the pill: change the start.
      Positioned(
        left: 0,
        top: 0,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_meOpen) {
                _edit(true);
              } else {
                setState(() => _meOpen = true);
                _closeMeLater();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutCubic,
              height: 22,
              padding: EdgeInsets.only(right: _meOpen ? 10 : 0),
              decoration: BoxDecoration(
                color: _meOpen ? Colors.white : Colors.white.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(11),
                boxShadow: _meOpen ? const [BoxShadow(color: Color(0x290F1E24), blurRadius: 8, offset: Offset(0, 2))] : const [],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 14,
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x662F6FDC), blurRadius: 5)],
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOutCubic,
                  child: _meOpen
                      ? Padding(padding: const EdgeInsets.only(left: 5), child: Text(_fromName,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.ink)))
                      : const SizedBox(height: 22),
                ),
              ]),
            ),
          ),
        ]),
      ),
      // on the edge of the card: + (add a stop) with 2 points; ⇅ (turn the order around) from 3 points
      Positioned(
        right: -6,
        top: air + 5 + _via.length * (_rowH + _gap) + (_rowH - 34) / 2,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: const Color(0x55000000),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _via.isEmpty ? _addStop : _swap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(_via.isEmpty ? Icons.add : Icons.swap_vert, size: 19, color: AppColors.ink),
            ),
          ),
        ),
      ),
    ]);
  }

  String get _toSub {
    final p = widget.place;
    if (p != null && p.address != _toName) return p.address;
    return '${_to.latitude.toStringAsFixed(4)}, ${_to.longitude.toStringAsFixed(4)}';
  }

  Widget _destRow(IconData icon, Color c, String title, String sub, VoidCallback onTap,
          {required bool plus, bool small = false}) =>
      SizedBox(
        height: _rowH,
        child: Row(children: [
          SizedBox(width: 22, child: Center(child: Icon(icon, color: c, size: small ? 13 : 19))),
          const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: Colors.white.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0x12131F2B)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: title,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 13 : 14.5, letterSpacing: -.2)),
                          if (sub.isNotEmpty)
                            TextSpan(text: '  $sub', style: const TextStyle(fontSize: 11, color: AppColors.soft)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (plus)
                      GestureDetector(
                        onTap: _addStop,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.add, size: 20, color: AppColors.soft),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );

  // ── vehicles (same tile as the sheets) ──
  double _secs(RouteResult r, Vehicle v) => v == _rv
      ? r.seconds // the route was made for this vehicle: its own time
      : switch (v) {
        Vehicle.bike => secondsFor(r.meters, 'bike'),
        Vehicle.ebike => secondsFor(r.meters, 'ebike'),
        Vehicle.scooter => secondsFor(r.meters, 'scooter'),
        Vehicle.moped => secondsFor(r.meters, 'moped'),
        Vehicle.moto => secondsFor(r.meters, 'moto'),
      };

  Place _tripPlace(RouteResult r) => Place(
        id: 'trip',
        type: PlaceType.rack,
        address: '',
        pos: _to,
        status: Status.free,
        distance: r.distance,
        accepts: const [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto],
        etaMin: {
          for (final v in const [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto])
            v: math.max(1, (_secs(r, v) / 60).round()),
        },
      );

  // ── Fast / Balanced / Quiet: a thin track, names only; the chosen one on a white thumb ──
  Widget _segmented() => Container(
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          for (final label in const ['Fast', 'Balanced', 'Quiet'])
            Expanded(
              child: Builder(builder: (_) {
                final i = _routes.indexWhere((x) => x.label == label);
                final on = i == _sel && i >= 0;
                final off = i < 0;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: off
                      ? null
                      : () {
                          setState(() => _sel = i);
                          _fit();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: on
                          ? const [BoxShadow(color: Color(0x1A0F1E24), blurRadius: 4, offset: Offset(0, 1))]
                          : const [],
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: off ? const Color(0xFFB4BEC2) : (on ? AppColors.ink : AppColors.soft))),
                  ),
                );
              }),
            ),
        ]),
      );

  bool get _bikeLike => _rv == Vehicle.bike || _rv == Vehicle.ebike || _rv == Vehicle.scooter;

  /// One route only (no Fast / Balanced / Quiet, no trip summary): Bike line or a chip chosen.
  bool get _oneRoute => _marked || _variant != 'standard';

  /// The pictures and names from the profile (My vehicle options).
  (String, String) _variantLook(String v) => switch ((v, _rv)) {
        ('ebike', _) => ('E-bike', 'assets/vehicles/opt_e.png'),
        ('two', _) => ('2 seats', 'assets/vehicles/opt_c2.png'),
        ('delivery', _) => ('Delivery', 'assets/vehicles/opt_cd.png'),
        ('trailer', _) => ('Trailer', 'assets/vehicles/opt_tr.png'),
        ('cargo', Vehicle.scooter) => ('Cargo basket', 'assets/vehicles/opt_sc.png'),
        ('cargo', Vehicle.moped) => ('Cargo delivery', 'assets/vehicles/opt_cm.png'),
        ('cargo', Vehicle.moto) => ('Top box & bags', 'assets/vehicles/opt_mc.png'),
        _ => ('Cargo box', 'assets/vehicles/opt_cb.png'),
      };

  /// Under the destination card, like the map chips, for the vehicle chosen below:
  /// bike: E-bike · 2 people · Delivery · Cargo · Trailer; scooter: Cargo; moped: Cargo; and last, Bike line.
  /// A chip chosen gives one route, the safest for it. Tap it again: back to Fast / Balanced / Quiet.
  Widget _variantChips() {
    Widget chip(String text, Widget icon, bool on, VoidCallback onTap, {Color? accent, Color? tint}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? (tint ?? AppColors.slateTint) : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: on ? (accent ?? AppColors.primary) : Colors.transparent, width: 1.3),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 5, offset: Offset(0, 1))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(width: 5),
                Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: on ? (accent ?? AppColors.ink) : AppColors.ink)),
              ]),
            ),
          ),
        );
    // the vehicle picture from the profile
    Widget look(String v) => Image.asset(_variantLook(v).$2,
        height: 18, errorBuilder: (_, __, ___) => const Icon(Icons.pedal_bike, size: 16));

    // once an option is chosen the whole row goes away; tap the vehicle below to bring it back
    if (_oneRoute) return const SizedBox.shrink();
    final variants = _vehiclePicked ? (routeVariants[_rv.name] ?? const <String>[]) : const <String>[];
    // a small round handle with » at the start shows that the row can be pushed away to the right
    // (drag it, or the row, to the right; a tap on it does the same). The chips scroll on their own.
    return Row(children: [
      GestureDetector(
        onTap: () => setState(() => _chipsAway = true),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(right: 6),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 5, offset: Offset(0, 1))],
          ),
          child: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 18, color: AppColors.soft),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final v in variants)
              chip(_variantLook(v).$1, look(v), _variant == v, () {
                setState(() => _variant = _variant == v ? 'standard' : v);
                _calc();
              }),
            if (_bikeLike || !_vehiclePicked)
              chip('Bike line', const BikeRoadIcon(size: 16), _marked, () {
                setState(() => _marked = !_marked);
                _calc();
              }, accent: AppColors.greenDark, tint: AppColors.greenTint),
          ]),
        ),
      ),
    ]);
  }

  // ── Parking near the destination ──
  bool _nearOpen = false;

  List<Place> get _nearDest {
    const d = Distance();
    final list = knownPlaces
        .where((p) => p.type.group == 'Parking' && d(_to, p.pos) <= 300 && (widget.place == null || p.id != widget.place!.id))
        .toList()
      ..sort((a, b) => d(_to, a.pos).compareTo(d(_to, b.pos)));
    return list.take(8).toList();
  }

  bool _hasBikeRoad(RouteResult r) => (_roadMix(r)['Protected lanes'] ?? 0) + (_roadMix(r)['Bike lanes'] ?? 0) > 0.05;

  Widget _cardHead(Widget left, bool open, VoidCallback onTap, {Widget? extra}) => InkWell(
        onTap: onTap,
        child: Row(children: [
          Expanded(child: left),
          if (extra != null) ...[extra, const SizedBox(width: 6)],
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.ink),
          ),
        ]),
      );

  Widget _nearCard(RouteResult r) {
    final near = _nearDest;
    const d = Distance();
    Widget dotted() => Expanded(
          child: LayoutBuilder(builder: (_, c) {
            final n = (c.maxWidth / 6).floor().clamp(1, 60);
            return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (int i = 0; i < n; i++)
                Container(width: 2.5, height: 2.5, decoration: const BoxDecoration(color: Color(0xFFAAB6BB), shape: BoxShape.circle)),
            ]);
          }),
        );
    return _softCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead(
          Row(children: [
            const Icon(Icons.local_parking_rounded, size: 16, color: AppColors.soft),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Parking near destination (${near.length})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.soft, fontSize: 13)),
            ),
          ]),
          _nearOpen,
          () => setState(() => _nearOpen = !_nearOpen),
          extra: _hasBikeRoad(r) ? const BikeRoadIcon(size: 18) : null,
        ),
        const SizedBox(height: 8),
        if (!_nearOpen)
          Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: const Color(0xFFE3E8EA), borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.route, size: 15, color: AppColors.soft),
            ),
            dotted(),
            for (final p in near.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Glyph(p.type, size: 22, color: colorsFor(p.shownStatus).main),
              ),
            if (near.isNotEmpty) dotted(),
            const DestinationPinIcon(size: 22),
          ])
        else if (near.isEmpty)
          const Text('No bike parking within 300 m of the destination.', style: TextStyle(color: AppColors.soft))
        else
          for (final p in near)
            InkWell(
              onTap: () {
                setState(() {
                  _to = p.pos;
                  _toName = p.address;
                });
                _calc();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Glyph(p.type, size: 24, color: colorsFor(p.shownStatus).main),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.address,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        '${d(_to, p.pos).round()} m · ${p.shownStatus == Status.full ? 'full' : '${p.count ?? '—'} free'}'
                        '${p.age.isEmpty ? '' : ' · ${p.age}'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
      ]),
    );
  }

  // ── Trip summary: weather on top, the colour band, then "Trip summary · ↗ climb · ↘ descent" ──
  static const _mixColors = {
    'Protected lanes': AppColors.green,
    'Quiet streets': Color(0xFF8CC063),
    'Bike lanes': AppColors.yellow,
    'Shared roads': Color(0xFFF08A3C),
    'Main roads': AppColors.red,
  };

  Widget _summaryCard(RouteResult r) {
    final mix = _roadMix(r);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                for (final e in mix.entries)
                  if (e.value > 0)
                    Expanded(
                      flex: math.max(1, (e.value * 1000).round()),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 400), color: _mixColors[e.key]),
                    ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('↗ ${r.climb} m  ↘ ${r.descent} m',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.soft)),
      ]),
    );
  }

  // ── bottom buttons ──
  /// ✕: leave this route and go back to search for something else; dark pill, same height as GO.
  Widget _cancelButton() => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x330F1E24), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Material(
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF34474F), Color(0xFF24333C)])),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(width: 64, height: 44, child: Icon(Icons.close_rounded, color: Colors.white, size: 22)),
            ),
          ),
        ),
      );

  Widget _roundBtn(IconData i, VoidCallback onTap, {Color color = AppColors.ink}) => Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFD5DDDF), width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(i, size: 20, color: color)),
        ),
      );

  Widget _goButton(RouteResult r) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => GuidanceScreen(
              route: r,
              to: _to,
              toName: _toName,
              place: widget.place,
              nearby: widget.nearby,
              suggestRack: _rack,
              destParking: _nearDest,
              vehicle: _rv.name,
            ),
          )),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.navigation_rounded, size: 18),
          label: const Text('GO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      );

  // Tap a box: type the place again (or pick "My location").
  Future<(String, LatLng)?> _pick(String hint, {bool allowMine = false}) => showModalBottomSheet<(String, LatLng)>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _PlacePicker(hint: hint, allowMine: allowMine),
      );

  Future<void> _edit(bool from) async {
    final r = await _pick(from ? 'Where from?' : 'Where to?', allowMine: true);
    if (r == null || !mounted) return;
    setState(() {
      if (from) {
        _fromName = r.$1;
        _from = r.$2;
      } else {
        _toName = r.$1;
        _to = r.$2;
      }
    });
    if (!from) _findRack();
    _calc();
  }

  Future<void> _addStop() async {
    final r = await _pick('Add a stop');
    if (r == null || !mounted) return;
    setState(() => _via.add(r));
    _calc();
  }

  Future<void> _editVia(int i) async {
    final r = await _pick('Change the stop (empty = remove)');
    if (!mounted) return;
    setState(() {
      if (r == null) {
        _via.removeAt(i);
      } else {
        _via[i] = r;
      }
    });
    _calc();
  }

  // Share of each kind of road, guessed from the street names on the route.
  Map<String, double> _roadMix(RouteResult r) {
    if (r.roadMix != null) return r.roadMix!;
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
          // the road types (they were under the arrow of the trip summary)
          for (final e in mix.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(children: [
                SizedBox(width: 118, child: Text(e.key, style: const TextStyle(fontSize: 12.5))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: e.value, minHeight: 6, backgroundColor: const Color(0xFFE3E8EA), color: _mixColors[e.key]),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${(e.value * 100).round()}%',
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          // saving the route moved here from the old ♡ next to GO
          StatefulBuilder(builder: (c, set) {
            final saved = Store.i.savedRoutes.any((s) => s.name == '$_fromName → $_toName');
            return OutlinedButton.icon(
              onPressed: saved
                  ? null
                  : () {
                      Store.i.saveRoute(SavedRoute('$_fromName → $_toName', _from, _to, r.meters, r.seconds));
                      set(() {});
                    },
              icon: Icon(saved ? Icons.favorite : Icons.favorite_border, color: AppColors.red, size: 18),
              label: Text(saved ? 'Saved' : 'Save route'),
            );
          }),
          const SizedBox(height: 8),
          Text(r.roadMix != null ? 'Road types from OpenStreetMap (Valhalla) · heights from Open-Meteo.' : 'Road types are estimated from street names until the map data answers.',
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
  final List<Place> destParking; // parking around the destination, shown when 500 m are left
  final String vehicle; // 'bike', 'ebike', 'scooter', 'moped', 'moto' (for recalculations)
  const GuidanceScreen({
    super.key,
    required this.route,
    required this.to,
    required this.toName,
    this.place,
    this.nearby = const [],
    this.suggestRack,
    this.destParking = const [],
    this.vehicle = 'bike',
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
  List<RouteControl> _controls = const []; // traffic lights and stop signs on the route
  Place? _statsPlace; // shown selected behind the Stats veil
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
  Weather? _wx; // for the compass's wind side

  // spoken directions (turn left / right …); the speaker button mutes them
  final _tts = FlutterTts();
  bool _muted = false;
  final Set<String> _said = {};

  // the whole route from above, with the road kinds (tap again: back to the normal guidance)
  bool _overview = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US').catchError((_) => null);
    _tts.setSpeechRate(0.5).catchError((_) => null);
    fetchWeather(_pos).then((w) {
      if (mounted) setState(() => _wx = w);
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _startGps();
    _loadControls();
    _loadRoadData();
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
    if (_follow && !_overview) {
      try {
        _map.move(p, math.max(_map.camera.zoom, _zoom));
      } catch (_) {}
    }

    _announce();
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

  Future<void> _loadControls() async {
    final route = _route;
    final c = await routeControls(route.points);
    if (mounted && identical(route, _route)) setState(() => _controls = c);
  }

  /// The next traffic light / stop sign ahead, with how far it is.
  (RouteControl, double, int)? _nextControl() {
    final ahead = _controls.where((c) => c.along > _along + 4).toList();
    if (ahead.isEmpty) return null;
    return (ahead.first, ahead.first.along - _along, ahead.length);
  }

  /// Says the next turn twice: about 200 m before it and right at it.
  void _announce() {
    if (_muted || _route.steps.isEmpty) return;
    final (step, dist, _) = _next();
    final street = step.street.isEmpty ? '' : ' onto ${step.street}';
    final key = '${step.at.latitude},${step.at.longitude}';
    if (dist <= 220 && dist > 60 && _said.add('far$key')) {
      _say('In ${(dist / 10).round() * 10} meters, ${step.text.toLowerCase()}$street');
    } else if (dist <= 30 && _said.add('now$key')) {
      _say('${step.text}$street');
    }
  }

  void _say(String t) {
    try {
      _tts.speak(t);
    } catch (_) {}
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) {
      _tts.stop().catchError((_) => null);
    } else {
      _say('Voice on');
    }
  }

  void _toggleOverview() {
    setState(() => _overview = !_overview);
    if (_overview) {
      _follow = false;
      try {
        _map.fitCamera(CameraFit.coordinates(
          coordinates: _route.points,
          padding: const EdgeInsets.fromLTRB(40, 190, 40, 200),
        ));
      } catch (_) {}
    } else {
      _follow = true;
      _map.move(_pos, _zoom);
    }
  }

  /// The route drawn by road kind: solid on bike lanes, · · · shared with cars, _ _ _ no markings.
  List<Polyline> _roadPolylines() => [
        for (final (pts, kind) in splitByRoad(_route))
          Polyline(
            points: pts,
            strokeWidth: 6,
            color: RoadLine.colors[kind] ?? AppColors.blue,
            pattern: kind == 'Protected lanes' || kind == 'Bike lanes'
                ? const StrokePattern.solid()
                : kind == 'Shared roads'
                    ? const StrokePattern.dotted(spacingFactor: 1.6)
                    : StrokePattern.dashed(segments: const [14, 9]),
          ),
      ];

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool on = false, String? tip}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: on ? AppColors.blue : Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: on ? Colors.white : AppColors.ink, semanticLabel: tip),
            ),
          ),
        ),
      );

  Widget _legend() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final k in const ['Protected lanes', 'Bike lanes', 'Shared roads', 'Quiet streets', 'Main roads'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                RoadLine(kind: k, width: 30),
                const SizedBox(width: 6),
                Text(
                    switch (k) {
                      'Protected lanes' => 'protected lane',
                      'Bike lanes' => 'bike lane',
                      'Shared roads' => 'shared with cars',
                      'Quiet streets' => 'no markings',
                      _ => 'main road, no markings',
                    },
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      );

  Widget _controlInBanner() {
    final n = _nextControl();
    if (n == null || n.$2 > 150) return const SizedBox.shrink();
    final (c, m, _) = n;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: TrafficControlIcon(kind: c.kind, size: 26),
        ),
        const SizedBox(height: 2),
        Text(fmtDistance(m), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  static const _roadShort = {
    'Protected lanes': 'protected lane',
    'Bike lanes': 'bike lane',
    'Quiet streets': 'quiet street',
    'Shared roads': 'shared road',
    'Main roads': 'main road',
  };

  Widget _rideStrip(Duration elapsed) {
    final road = _roadNow();
    final rel = _nextRelief();
    final relColor = rel == null
        ? AppColors.soft
        : rel.$1 == 'hill'
            ? AppColors.greenDark
            : rel.$1 == 'downhill'
                ? AppColors.blue
                : AppColors.slate;
    final relIcon = rel == null ? '' : (rel.$1 == 'hill' ? '↗ ' : rel.$1 == 'downhill' ? '↘ ' : '⌒ ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        RoadLine(kind: road, width: 30),
        const SizedBox(width: 4),
        Text(_roadShort[road] ?? '…',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: road == 'Bike lanes' ? AppColors.yellowDark : (RoadLine.colors[road] ?? AppColors.soft))),
        const SizedBox(width: 12),
        Text(_speed.toStringAsFixed(1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const Text(' km/h', style: TextStyle(fontSize: 11, color: AppColors.soft)),
        const SizedBox(width: 12),
        Text('${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const Spacer(),
        Text(rel == null ? '— flat' : '$relIcon${fmtDistance(rel.$2)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: relColor)),
      ]),
    );
  }

  /// The kind of road we are on now (from the map data), '' while it loads.
  String _roadNow() {
    final segs = _route.roadSegs;
    if (segs == null || segs.isEmpty) return '';
    for (final s in segs) {
      if (s.$1 > _along) return s.$2;
    }
    return segs.last.$2;
  }

  /// The next hill, downhill or bridge ahead: (what, metres to it).
  (String, double)? _nextRelief() {
    String? what;
    double? best;
    for (final b in _route.bridges ?? const <(double, double)>[]) {
      if (b.$2 > _along) {
        best = math.max(0, b.$1 - _along);
        what = 'bridge';
        break;
      }
    }
    final e = _route.elev;
    if (e != null) {
      for (int i = 1; i < e.length; i++) {
        final a = e[i - 1], b = e[i];
        if (b.$1 <= _along) continue;
        final dx = b.$1 - a.$1;
        if (dx <= 0) continue;
        final g = (b.$2 - a.$2) / dx; // 3 % or more counts
        if (g.abs() >= 0.03) {
          final d = math.max(0.0, a.$1 - _along);
          if (best == null || d < best) {
            best = d;
            what = g > 0 ? 'hill' : 'downhill';
          }
          break;
        }
      }
    }
    return best == null ? null : (what!, best);
  }

  void _loadRoadData() {
    final r = _route;
    Future.wait([addRoadMix(r), addElevation(r)]).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _recalculate() async {
    setState(() => _recalc = true);
    final r = await bikeRoute([_pos, _to], vehicle: widget.vehicle);
    if (!mounted) return;
    setState(() {
      if (r != null) {
        _route = r;
        _along = 0;
      }
      _recalc = false;
      _offCount = 0;
      _controls = const [];
    });
    _loadControls();
    _loadRoadData();
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
      // keep the map underneath: the place pin is shown big behind the veil
      setState(() => _statsPlace = stats);
      try {
        _map.move(stats.pos, _zoom);
      } catch (_) {}
      await showStats(context, stats);
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
  Future<void> _rideToRack() => _rideTo(widget.suggestRack!);

  Future<void> _rideTo(Place rack) async {
    final wasArrived = _arrived;
    _sim?.cancel();
    final r = await bikeRoute([_pos, rack.pos], vehicle: widget.vehicle);
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
      _simulating = false;
    });
    if (wasArrived) _startGps();
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
    _tts.stop().catchError((_) => null);
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
    final (step, dist, _) = _next();
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
            baseTiles(street: true),
            if (_overview && _route.roadSegs != null)
              PolylineLayer(polylines: _roadPolylines())
            else
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
              if (_statsPlace != null)
                Marker(
                  point: _statsPlace!.pos,
                  width: PlacePin.width,
                  height: PlacePin.height,
                  alignment: Alignment.topCenter,
                  child: PlacePin(place: _statsPlace!, selected: true),
                ),
              // traffic lights and stop signs still ahead on the route
              for (final c in _controls.where((c) => c.along > _along + 4))
                Marker(
                  point: c.at,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
                    ),
                    alignment: Alignment.center,
                    child: TrafficControlIcon(kind: c.kind, size: 15),
                  ),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    // the next traffic light / stop sign: only in the last 150 m before it
                    _controlInBanner(),
                    const Icon(Icons.format_list_bulleted, color: Colors.white),
                  ]),
                ),
              ),
            ),
            // the ride strip, glued under the banner: road now (live line), speed, time, next hill/bridge
            _rideStrip(elapsed),
            if (_recalc)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
                child: const Text('Recalculating…', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
        // next traffic light / stop sign, under the turn banner on the right; the compass under it
        // (tap the compass: wind instead of our direction, tap again: back)
        Positioned(
          right: 12,
          top: top + 132,
          child: RideCompass(heading: _heading, windKmh: _wx?.wind, windFrom: _wx?.windDir, size: 70),
        ),
        Positioned(
          right: 10,
          bottom: 104,
          child: Column(children: [
            // the whole route from above with the road kinds; tap again: back to the normal guidance
            _roundBtn(_overview ? Icons.navigation_rounded : Icons.alt_route, _toggleOverview,
                on: _overview, tip: 'Whole route'),
            // spoken directions on / off
            _roundBtn(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, _toggleMute,
                on: _muted, tip: 'Voice'),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'sim',
              backgroundColor: _simulating ? AppColors.blue : Colors.white,
              foregroundColor: _simulating ? Colors.white : AppColors.ink,
              tooltip: 'Simulate the ride',
              onPressed: _toggleSim,
              child: Icon(_simulating ? Icons.pause : Icons.play_arrow),
            ),
            if (!_follow && !_overview)
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
        if (_overview) Positioned(left: 10, bottom: 104, child: _legend()),
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

/// Stats: over the map, a light dark veil and three big 3D buttons
/// (green, yellow, red) one under the other. No text, no confirmation:
/// tap one, it presses down, the place takes that colour.
Future<void> showStats(BuildContext context, Place place) {
  HapticFeedback.mediumImpact(); // the phone vibrates when it appears
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Later',
    barrierColor: const Color(0x660F1E24),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _StatsOverlay(place: place),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
    ),
  );
}

class _StatsOverlay extends StatefulWidget {
  final Place place;
  const _StatsOverlay({required this.place});
  @override
  State<_StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<_StatsOverlay> {
  Status? _pressed;

  Future<void> _pick(Status s) async {
    setState(() => _pressed = s);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 260));
    Store.i.confirm(widget.place.id, s);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _ball(Status s, Color c1, Color c2, Color dd) {
    final down = _pressed == s;
    return GestureDetector(
      onTap: _pressed == null ? () => _pick(s) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 104,
        height: 104,
        margin: EdgeInsets.only(top: down ? 8 : 0, bottom: down ? 0 : 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.3, -0.4), radius: 0.9, colors: [c1, c2]),
          boxShadow: [
            BoxShadow(color: dd, offset: Offset(0, down ? 1 : 9)),
            BoxShadow(color: const Color(0x55000000), offset: Offset(0, down ? 3 : 14), blurRadius: down ? 6 : 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _ball(Status.free, const Color(0xFF93C96E), AppColors.green, const Color(0xFF3B7420)),
          const SizedBox(height: 22),
          _ball(Status.almost, const Color(0xFFFFD866), AppColors.yellow, const Color(0xFFB07F00)),
          const SizedBox(height: 22),
          _ball(Status.full, const Color(0xFFFF8A8D), AppColors.red, const Color(0xFFA82328)),
        ]),
      ),
    );
  }
}


/// Small search used by the route boxes.
class _PlacePicker extends StatefulWidget {
  final String hint;
  final bool allowMine;
  const _PlacePicker({required this.hint, required this.allowMine});
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  Timer? _wait;
  List<GeoResult> _results = [];
  String _q = '';

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _q = q.trim();
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 350), () async {
      if (_q.length < 3) return;
      final asked = _q;
      final r = await searchUs(asked, near: userPos);
      if (mounted && asked == _q) setState(() => _results = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ours = _q.length < 2
        ? <Place>[]
        : knownPlaces.where((p) => p.address.toLowerCase().contains(_q.toLowerCase())).take(4).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          onChanged: _changed,
          onSubmitted: (_) {
            if (_results.isNotEmpty) Navigator.pop(context, (_results.first.title, _results.first.pos));
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.paper,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: ListView(shrinkWrap: true, children: [
            if (widget.allowMine)
              ListTile(
                leading: const Icon(Icons.my_location, color: AppColors.blue),
                title: const Text('My location', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, ('My location', userPos)),
              ),
            for (final p in ours)
              ListTile(
                leading: Glyph(p.type, size: 22, color: colorsFor(p.shownStatus).dark),
                title: Text(p.address),
                subtitle: Text(p.type.title),
                onTap: () => Navigator.pop(context, (p.address, p.pos)),
              ),
            for (final g in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${fmtDistance(const Distance()(userPos, g.pos))} · ${g.subtitle}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, (g.title, g.pos)),
              ),
          ]),
        ),
      ]),
    );
  }
}


/// The road between my location and the destination, drawn like the Routes sign in the bottom menu:
/// it leaves the dot to the right, makes one hairpin back to the left, goes down and turns right into the
/// icon at the end. Blue at the start, red at the end, with a thin white edge like the route on the map.
/// When [from] and [to] are in one column (between a stop and the flag) it is a short straight piece.
class _WavyWire extends CustomPainter {
  final Offset from, to;
  const _WavyWire({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if ((to.dx - from.dx).abs() < 1) {
      path
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
    } else {
      const r = 5.0;
      final x0 = from.dx, y0 = from.dy - 7; // the middle of the dot
      final left = x0 - r; // the vertical part, a little left of the dot
      path
        ..moveTo(x0, y0)
        ..lineTo(x0 + r + 2, y0)
        ..arcToPoint(Offset(x0 + r + 2, y0 + 2 * r), radius: const Radius.circular(r)) // hairpin to the left
        ..lineTo(x0, y0 + 2 * r)
        ..arcToPoint(Offset(left, y0 + 3 * r), radius: const Radius.circular(r), clockwise: false)
        ..lineTo(left, to.dy - r)
        ..arcToPoint(Offset(left + r, to.dy), radius: const Radius.circular(r), clockwise: false)
        ..lineTo(to.dx, to.dy);
    }
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.blue, AppColors.red],
      ).createShader(Rect.fromLTRB(0, from.dy - 7, 1, to.dy));
    canvas.drawPath(path, edge);
    canvas.drawPath(path, road);
  }

  @override
  bool shouldRepaint(_WavyWire old) => old.from != from || old.to != to;
}
