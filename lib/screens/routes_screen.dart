import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/routing.dart';
import '../theme.dart';
import '../widgets/directions.dart';
import '../widgets/tiles.dart';

/// A ride past well-known places. The line itself is calculated by the bike
/// router through these landmarks, so it follows real streets and trails.
class Landmark {
  final String name;
  final LatLng pos;
  const Landmark(this.name, this.pos);
}

class ExploreRoute {
  final String name;
  final String level; // Easy / Medium
  final String about;
  final List<Landmark> stops;
  const ExploreRoute(this.name, this.level, this.about, this.stops);
}

const exploreRoutes = [
  ExploreRoute('Lakefront Trail North', 'Easy', 'Along the lake, beaches and harbors', [
    Landmark('Navy Pier', LatLng(41.8917, -87.6086)),
    Landmark('Oak Street Beach', LatLng(41.9028, -87.6240)),
    Landmark('North Avenue Beach', LatLng(41.9145, -87.6233)),
    Landmark('Diversey Harbor', LatLng(41.9310, -87.6330)),
    Landmark('Montrose Harbor', LatLng(41.9640, -87.6380)),
  ]),
  ExploreRoute('The 606 Trail', 'Easy', 'Elevated park trail across four neighborhoods', [
    Landmark('Ridgeway trailhead', LatLng(41.9139, -87.7204)),
    Landmark('Humboldt Blvd', LatLng(41.9139, -87.7020)),
    Landmark('Western Ave', LatLng(41.9139, -87.6870)),
    Landmark('Walsh Park', LatLng(41.9139, -87.6680)),
  ]),
  ExploreRoute('Museum Campus Loop', 'Easy', 'Fountain, museums and skyline views', [
    Landmark('Buckingham Fountain', LatLng(41.8758, -87.6189)),
    Landmark('Field Museum', LatLng(41.8663, -87.6170)),
    Landmark('Shedd Aquarium', LatLng(41.8676, -87.6140)),
    Landmark('Adler Planetarium', LatLng(41.8663, -87.6068)),
  ]),
  ExploreRoute('Loop Landmarks & Riverwalk', 'Medium', 'The Bean, the river and the tallest tower', [
    Landmark('Cloud Gate (The Bean)', LatLng(41.8827, -87.6233)),
    Landmark('Chicago Riverwalk', LatLng(41.8875, -87.6260)),
    Landmark('Merchandise Mart', LatLng(41.8885, -87.6354)),
    Landmark('Willis Tower', LatLng(41.8789, -87.6359)),
  ]),
  ExploreRoute('Lincoln Park Loop', 'Easy', 'Zoo, conservatory and the pond', [
    Landmark('Lincoln Park Zoo', LatLng(41.9211, -87.6340)),
    Landmark('Lincoln Park Conservatory', LatLng(41.9244, -87.6355)),
    Landmark('North Pond', LatLng(41.9295, -87.6370)),
    Landmark('Diversey Harbor', LatLng(41.9310, -87.6330)),
  ]),
  ExploreRoute('Hyde Park & Jackson Park', 'Medium', 'Point views, museum and the Japanese garden', [
    Landmark('Promontory Point', LatLng(41.7943, -87.5770)),
    Landmark('Museum of Science and Industry', LatLng(41.7906, -87.5831)),
    Landmark('Garden of the Phoenix', LatLng(41.7837, -87.5805)),
  ]),
];

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});
  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _map = MapController();
  final Map<String, RouteResult?> _results = {};
  final Set<String> _loading = {};
  int _sel = 0;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _calc(0, fit: true);
  }

  Future<void> _calc(int i, {bool fit = false}) async {
    final e = exploreRoutes[i];
    if (_results[e.name] == null && !_loading.contains(e.name)) {
      setState(() => _loading.add(e.name));
      final r = await bikeRoute([for (final s in e.stops) s.pos]);
      if (!mounted) return;
      setState(() {
        _loading.remove(e.name);
        _results[e.name] = r;
      });
    }
    if (fit) _fit(i);
  }

  void _fit(int i) {
    if (!_mapReady) return;
    final e = exploreRoutes[i];
    final pts = _results[e.name]?.points ?? [for (final s in e.stops) s.pos];
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(36)));
  }

  void _select(int i) {
    setState(() => _sel = i);
    _calc(i, fit: true);
  }

  @override
  Widget build(BuildContext context) {
    final e = exploreRoutes[_sel];
    final r = _results[e.name];
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Explore', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Rides past Chicago landmarks, on bike-friendly streets and trails.',
              style: TextStyle(color: AppColors.soft)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: e.stops.first.pos,
                  initialZoom: 13,
                  onMapReady: () {
                    _mapReady = true;
                    _fit(_sel);
                  },
                ),
                children: [
                  baseTiles(),
                  if (r != null) routeLayer(r.points),
                  MarkerLayer(markers: [
                    for (final (i, s) in e.stops.indexed)
                      Marker(
                        point: s.pos,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.blue, width: 2.5),
                          ),
                          alignment: Alignment.center,
                          child: Text('${i + 1}',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.blue)),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 20), children: [
            for (final (i, x) in exploreRoutes.indexed) _card(i, x),
          ]),
        ),
      ]),
    );
  }

  Widget _card(int i, ExploreRoute x) {
    final sel = i == _sel;
    final r = _results[x.name];
    final busy = _loading.contains(x.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _select(i),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? AppColors.blue : Colors.transparent, width: 2),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: x.level == 'Easy' ? AppColors.greenTint : AppColors.yellowTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(x.level,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: x.level == 'Easy' ? AppColors.greenDark : AppColors.yellowDark)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(x.about, style: const TextStyle(color: AppColors.soft, fontSize: 12.5)),
              const SizedBox(height: 6),
              Text(x.stops.map((s) => s.name).join(' → '),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                if (busy)
                  const Text('Calculating…', style: TextStyle(color: AppColors.soft))
                else if (r != null)
                  Text('${r.distance} · ${r.duration}',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.blue))
                else if (_results.containsKey(x.name))
                  const Text('Route not available, tap to retry', style: TextStyle(color: AppColors.redDark))
                else
                  const Text('Tap to see the route', style: TextStyle(color: AppColors.soft)),
                const Spacer(),
                if (r != null)
                  FilledButton(
                    onPressed: () => showDirections(context, r, x.name),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.blue, minimumSize: const Size(64, 40)),
                    child: const Text('GO'),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
