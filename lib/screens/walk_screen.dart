import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/routing.dart';
import '../theme.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart' show openLink;
import '../widgets/share_pin.dart';
import '../widgets/share_sheet.dart';
import '../widgets/tiles.dart';

/// Walking to a shared bike or scooter: no turn-by-turn. A dotted line on the map,
/// the minutes on it, and one short message at the bottom that changes as you get close.
class WalkScreen extends StatefulWidget {
  final Place place;
  const WalkScreen({super.key, required this.place});

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

const _compass = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'];

class _WalkScreenState extends State<WalkScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _gps;
  late LatLng _pos = userPos;
  List<LatLng> _path = const [];
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _path = [_pos, widget.place.pos];
    footPath(_pos, widget.place.pos).then((w) {
      if (!mounted) return;
      setState(() => _path = w);
      _fit();
    });
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

  void _fit() {
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([_pos, ..._path, widget.place.pos]),
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 190),
        maxZoom: 17.5,
      ));
      _fitted = true;
    } catch (_) {}
  }

  /// metres still to walk: along the path from the point nearest to me
  double get _left {
    const d = Distance();
    if (_path.length < 2) return d(_pos, widget.place.pos);
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
    if (_path.length < 2) return widget.place.pos;
    const d = Distance();
    var total = 0.0;
    for (var i = 0; i < _path.length - 1; i++) {
      total += d(_path[i], _path[i + 1]);
    }
    return pointAlong(_path, total / 2);
  }

  /// One short, friendly line. No "turn left in 50 m".
  (String, String) _message(double m) {
    final p = widget.place, s = p.share!;
    final what = s.street ? 'the ${s.vehicle.label.toLowerCase()}' : 'the station';
    final op = p.operatorName ?? 'the operator';
    if (m < 25) return ('You are here', 'Unlock it in the $op app.');
    if (m < 90) return ('Almost there', 'Look for $what on this block.');
    final dir = _compass[(((bearing(_pos, p.pos) + 360) % 360) / 45).round() % 8];
    return ('${walkMinutes(m)} min walk', '${fmtDistance(m)} · head $dir, follow the dotted line.');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final left = _left;
    final (title, sub) = _message(left);
    final here = left < 25;
    final top = MediaQuery.of(context).padding.top;
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
                strokeWidth: 5,
                color: AppColors.blue,
                pattern: const StrokePattern.dotted(spacingFactor: 2),
              ),
            ]),
            MarkerLayer(markers: [
              Marker(point: _pos, width: 34, height: 34, child: const UserDot()),
              Marker(
                point: p.pos,
                width: SharePin.widthFor(p),
                height: SharePin.height,
                alignment: Alignment.topCenter,
                child: SharePin(place: p, selected: true),
              ),
              if (!here && _path.length > 1)
                Marker(
                  point: _middle,
                  width: 84,
                  height: 30,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.directions_walk_rounded, size: 15, color: Colors.white),
                      const SizedBox(width: 2),
                      Text('${walkMinutes(left)} min',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                ),
            ]),
          ],
        ),
        // close: top left
        Positioned(
          top: top + 10,
          left: 12,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context),
              child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.close_rounded, size: 22)),
            ),
          ),
        ),
        // the message: one low card
        Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x260F1E24), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: here ? AppColors.greenTint : AppColors.slateTint, shape: BoxShape.circle),
                child: Icon(here ? Icons.check_rounded : Icons.directions_walk_rounded,
                    color: here ? AppColors.greenDark : AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.soft)),
                  const SizedBox(height: 2),
                  Text(p.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ]),
              ),
              if (here)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () => openLink(operatorUrl(p)),
                  child: Text('Open ${p.operatorName ?? 'app'}'),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
