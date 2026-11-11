import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/routing.dart';
import '../data/weather.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart' show openLink;
import '../widgets/share_pin.dart';
import '../widgets/share_sheet.dart';
import '../widgets/tiles.dart';
import '../widgets/wx_button.dart';
import 'map_extras.dart' show showWeather;

/// Walking to a shared bike or scooter: no turn-by-turn. A dashed line on the map,
/// the minutes on it, and one short message at the bottom that changes as you get close.
/// The other shared bikes and stations around stay on the map: a tap on one walks there instead.
/// Top right: the weather and your vehicle, as on the map. The X sits in the message card.
class WalkScreen extends StatefulWidget {
  final Place place;
  final List<Place> others;
  final Weather? wx;
  final Vehicle vehicle;
  const WalkScreen({
    super.key,
    required this.place,
    this.others = const [],
    this.wx,
    this.vehicle = Vehicle.bike,
  });

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

const _compass = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'];

class _WalkScreenState extends State<WalkScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _gps;
  late LatLng _pos = userPos;
  late Place _place = widget.place; // where we are walking now
  List<LatLng> _path = const [];
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _route(fit: true);
    try {
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 4),
      ).listen((p) {
        if (mounted) setState(() => _pos = LatLng(p.latitude, p.longitude));
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  /// the foot path to the place we are walking to now
  void _route({bool fit = false}) {
    final to = _place;
    _path = [_pos, to.pos];
    footPath(_pos, to.pos).then((w) {
      if (!mounted || !identical(to, _place)) return;
      setState(() => _path = w);
      if (fit) _fit();
    });
  }

  /// another shared bike or station was tapped: walk there instead
  void _walkTo(Place p) {
    setState(() => _place = p);
    _route();
  }

  void _fit() {
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([_pos, ..._path, _place.pos]),
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 190),
        maxZoom: 17.5,
      ));
      _fitted = true;
    } catch (_) {}
  }

  /// metres still to walk: along the path from the point nearest to me
  double get _left {
    const d = Distance();
    if (_path.length < 2) return d(_pos, _place.pos);
    var best = 0, bestM = double.infinity;
    for (var i = 0; i < _path.length; i++) {
      final m = d(_pos, _path[i]);
      if (m < bestM) {
        bestM = m;
        best = i;
      }
    }
    var sum = bestM;
    for (var i = best; i < _path.length - 1; i++) {
      sum += d(_path[i], _path[i + 1]);
    }
    return sum;
  }

  /// the middle of the path: where the minutes bubble sits
  LatLng get _middle {
    if (_path.length < 2) return _place.pos;
    const d = Distance();
    var total = 0.0;
    for (var i = 0; i < _path.length - 1; i++) {
      total += d(_path[i], _path[i + 1]);
    }
    return pointAlong(_path, total / 2);
  }

  /// One short, friendly line. No "turn left in 50 m".
  (String, String) _message(double m) {
    final p = _place, s = p.share!;
    final what = s.street ? 'the ${s.vehicle.label.toLowerCase()}' : 'the station';
    final op = p.operatorName ?? 'the operator';
    if (m < 25) return ('You are here', 'Unlock it in the $op app.');
    if (m < 90) return ('Almost there', 'Look for $what on this block.');
    final dir = _compass[(((bearing(_pos, p.pos) + 360) % 360) / 45).round() % 8];
    return ('${walkMinutes(m)} min walk', '${fmtDistance(m)} · head $dir, follow the dashed line.');
  }

  @override
  Widget build(BuildContext context) {
    final p = _place;
    final left = _left;
    final (title, sub) = _message(left);
    final here = left < 25;
    final top = MediaQuery.of(context).padding.top;
    // every share place around, the one we walk to drawn last (on top, opened, dark)
    final around = [
      if (!identical(p, widget.place)) widget.place,
      for (final o in widget.others)
        if (o.id != p.id) o,
    ];
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _pos,
            initialZoom: 16.5,
            onMapReady: () {
              if (!_fitted) _fit();
            },
          ),
          children: [
            baseTiles(street: true),
            PolylineLayer(polylines: [
              Polyline(
                points: _path,
                strokeWidth: 4,
                color: AppColors.soft,
                pattern: StrokePattern.dashed(segments: const [10, 7]),
              ),
            ]),
            MarkerLayer(markers: [
              for (final o in around)
                Marker(
                  point: o.pos,
                  width: SharePin.widthFor(o),
                  height: SharePin.height,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(onTap: () => _walkTo(o), child: SharePin(place: o)),
                ),
              Marker(point: _pos, width: 34, height: 34, child: const UserDot()),
              Marker(
                point: p.pos,
                width: SharePin.widthFor(p, open: true),
                height: SharePin.height,
                alignment: Alignment.topCenter,
                child: SharePin(place: p, selected: true, open: true),
              ),
              if (!here && _path.length > 1)
                Marker(
                  point: _middle,
                  width: WalkBubble.width,
                  height: WalkBubble.height,
                  child: IgnorePointer(child: WalkBubble(walkMinutes(left))),
                ),
            ]),
          ],
        ),
        // top right: the weather and your vehicle, as on the map
        Positioned(
          top: top + 44,
          right: kEdge,
          child: WxVehicleButton(
            wx: widget.wx,
            vehicle: widget.vehicle,
            onWeather: widget.wx == null ? null : () => showWeather(context, widget.wx!),
          ),
        ),
        // the message: one low card, with the X in its right corner
        Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x260F1E24), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: here
                    ? Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(color: AppColors.greenTint, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: AppColors.greenDark),
                      )
                    : const WalkerDot(size: 42),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.soft)),
                    const SizedBox(height: 2),
                    Text(p.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    if (here) ...[
                      const SizedBox(height: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                        onPressed: () => openLink(operatorUrl(p)),
                        child: Text('Open ${p.operatorName ?? 'app'}'),
                      ),
                    ],
                  ]),
                ),
              ),
              // close: in the right corner of the card
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 24, color: AppColors.ink),
                tooltip: 'Close',
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
