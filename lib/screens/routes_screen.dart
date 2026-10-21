import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_state.dart';
import '../data/location.dart';
import '../data/routing.dart';
import '../data/store.dart';
import '../theme.dart';
import '../widgets/directions.dart';
import '../widgets/sheet_parts.dart';
import '../widgets/tiles.dart';
import 'trip_screen.dart';

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
  final String kind; // urban park, landmark…
  final int asphalt; // % paved
  final List<String> facilities;
  final String hours;
  const ExploreRoute(this.name, this.level, this.about, this.stops,
      {this.kind = 'Urban park', this.asphalt = 95, this.facilities = const ['🧺 Picnic', '🚰 Water'], this.hours = '6:00–23:00'});

  bool get openNow {
    final h = DateTime.now().hour;
    return h >= 6 && h < 23;
  }
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


/// Routes tab: Plan · Explore · Saved.
class RoutesScreen extends StatefulWidget {
  final AppState state;
  const RoutesScreen({super.key, required this.state});
  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  String _seg = 'Explore';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Routes', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Plan', label: Text('Plan')),
              ButtonSegment(value: 'Explore', label: Text('Explore')),
              ButtonSegment(value: 'Saved', label: Text('Saved')),
            ],
            selected: {_seg},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_seg) {
            'Plan' => PlanView(state: widget.state),
            'Saved' => const SavedRoutesView(),
            _ => const ExploreView(),
          },
        ),
      ]),
    );
  }
}

// ───────────────────────── Plan ─────────────────────────

class PlanView extends StatefulWidget {
  final AppState state;
  const PlanView({super.key, required this.state});
  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
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
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Row(children: [
            Icon(Icons.my_location, color: AppColors.blue, size: 18),
            SizedBox(width: 8),
            Text('Start', style: TextStyle(color: AppColors.soft)),
            SizedBox(width: 10),
            Text('My location', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const Divider(),
          TextField(
            onChanged: _changed,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.place, color: AppColors.red),
              hintText: 'End: address or place',
              border: InputBorder.none,
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      for (final r in _results)
        Card(
          color: Colors.white,
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => startTrip(context, to: r.pos, toName: r.title, myVehicle: widget.state.myVehicle),
          ),
        ),
      if (_results.isEmpty) ...[
        const SizedBox(height: 10),
        const Text('Quick picks', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.soft)),
        for (final e in exploreRoutes.take(4))
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(e.stops.last.name),
            subtitle: Text(e.name),
            onTap: () => startTrip(context, to: e.stops.last.pos, toName: e.stops.last.name, myVehicle: widget.state.myVehicle),
          ),
      ],
    ]);
  }
}

// ───────────────────────── Explore ─────────────────────────

final Map<String, RouteResult?> _exploreCache = {};

Future<RouteResult?> _exploreRoute(ExploreRoute e) async {
  if (_exploreCache[e.name] != null) return _exploreCache[e.name];
  final r = await bikeRoute([for (final s in e.stops) s.pos]);
  _exploreCache[e.name] = r;
  return r;
}

class ExploreView extends StatefulWidget {
  const ExploreView({super.key});
  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  String _level = 'All';
  String _length = 'Any length';
  bool _openNow = false;

  @override
  void initState() {
    super.initState();
    for (final e in exploreRoutes) {
      _exploreRoute(e).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = exploreRoutes.where((e) {
      if (_level != 'All' && e.level != _level) return false;
      if (_openNow && !e.openNow) return false;
      final km = (_exploreCache[e.name]?.meters ?? 0) / 1000;
      if (_length == '< 10 km' && km >= 10) return false;
      if (_length == '10–20 km' && (km < 10 || km > 20)) return false;
      if (_length == '20+ km' && km <= 20) return false;
      return true;
    }).toList();
    return Column(children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final l in const ['All', 'Easy', 'Medium'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(l), selected: _level == l, onSelected: (_) => setState(() => _level = l)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: PopupMenuButton<String>(
              onSelected: (v) => setState(() => _length = v),
              itemBuilder: (_) => [
                for (final v in const ['Any length', '< 10 km', '10–20 km', '20+ km']) PopupMenuItem(value: v, child: Text(v)),
              ],
              child: Chip(label: Text(_length), avatar: const Icon(Icons.straighten, size: 16)),
            ),
          ),
          FilterChip(label: const Text('Open now'), selected: _openNow, onSelected: (v) => setState(() => _openNow = v)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 20), children: [
          for (final e in list) _card(e),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No routes match these filters.', textAlign: TextAlign.center),
            ),
        ]),
      ),
    ]);
  }

  Widget _card(ExploreRoute x) {
    final r = _exploreCache[x.name];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExploreDetail(route: x))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    r == null
                        ? '${x.level} · calculating…'
                        : '${x.level} · ${r.distance} · ${r.duration}',
                    style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(x.stops.map((s) => s.name).join(' → '),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: r == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => GuidanceScreen(route: r, to: x.stops.last.pos, toName: x.name),
                        )),
                style: FilledButton.styleFrom(backgroundColor: AppColors.blue, minimumSize: const Size(60, 44)),
                child: const Text('GO'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class ExploreDetail extends StatefulWidget {
  final ExploreRoute route;
  const ExploreDetail({super.key, required this.route});
  @override
  State<ExploreDetail> createState() => _ExploreDetailState();
}

class _ExploreDetailState extends State<ExploreDetail> {
  final _map = MapController();
  RouteResult? _r;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _exploreRoute(widget.route).then((r) {
      if (!mounted) return;
      setState(() => _r = r);
      _fit();
    });
  }

  void _fit() {
    if (!_ready) return;
    final pts = _r?.points ?? [for (final s in widget.route.stops) s.pos];
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(30)));
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.route;
    final r = _r;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: Text(x.name)),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SizedBox(
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: x.stops.first.pos,
                initialZoom: 13,
                onMapReady: () {
                  _ready = true;
                  _fit();
                },
              ),
              children: [
                baseTiles(),
                if (r != null) routeLayer(r.points),
                MarkerLayer(markers: [
                  for (final (i, s) in x.stops.indexed)
                    Marker(
                      point: s.pos,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.blue, width: 2.5),
                        ),
                        alignment: Alignment.center,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.blue)),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text('${x.level} · ${x.kind}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          Icon(Icons.circle, size: 10, color: x.openNow ? AppColors.green : AppColors.red),
          const SizedBox(width: 4),
          Text(x.openNow ? 'Open · ${x.hours}' : 'Closed · ${x.hours}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FactTile(r?.distance ?? '—', 'distance')),
          const SizedBox(width: 6),
          Expanded(child: FactTile(r?.duration ?? '—', 'duration')),
          const SizedBox(width: 6),
          Expanded(child: FactTile(r == null ? '—' : '${r.climb} m', 'climb')),
        ]),
        const SizedBox(height: 10),
        Text('Asphalt ${x.asphalt}% · Gravel ${100 - x.asphalt}%', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [for (final f in x.facilities) Chip(label: Text(f))]),
        const SizedBox(height: 6),
        const Text('Stops', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final (i, s) in x.stops.indexed) Text('${i + 1}. ${s.name}'),
        const SizedBox(height: 10),
        const Text('Leaderboard', style: TextStyle(fontWeight: FontWeight.w800)),
        const Text('1  Andrei · 41:20\n2  Maria · 43:05\n3  Dan · 47:12'),
        const SizedBox(height: 14),
        Row(children: [
          IconButton.outlined(
            onPressed: r == null
                ? null
                : () {
                    Store.i.saveRoute(SavedRoute(x.name, x.stops.first.pos, x.stops.last.pos, r.meters, r.seconds));
                    setState(() {});
                  },
            icon: Icon(Store.i.savedRoutes.any((s) => s.name == x.name) ? Icons.favorite : Icons.favorite_border,
                color: AppColors.red),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: r == null
                  ? null
                  : () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => GuidanceScreen(route: r, to: x.stops.last.pos, toName: x.name),
                      )),
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
              child: const Text('GO'),
            ),
          ),
        ]),
        if (r != null)
          TextButton(onPressed: () => showDirections(context, r, x.name), child: const Text('Turn-by-turn list')),
      ]),
    );
  }
}

// ───────────────────────── Saved ─────────────────────────

class SavedRoutesView extends StatefulWidget {
  const SavedRoutesView({super.key});
  @override
  State<SavedRoutesView> createState() => _SavedRoutesViewState();
}

class _SavedRoutesViewState extends State<SavedRoutesView> {
  SavedRoute? _sel;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = Store.i.savedRoutes.where((r) => r.name.toLowerCase().contains(_q.toLowerCase())).toList();
    final sel = _sel ?? (all.isEmpty ? null : all.first);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            hintText: 'Search routes…',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: all.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No saved routes yet. Tap ♡ when you choose a route.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.soft)),
                ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), children: [
                for (final r in all)
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: r == sel ? AppColors.blue : Colors.transparent, width: 2),
                    ),
                    child: ListTile(
                      onTap: () => setState(() => _sel = r),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${fmtDistance(r.meters)} · ${fmtMinutes(r.seconds / 60)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: AppColors.red),
                        onPressed: () => setState(() {
                          if (_sel == r) _sel = null;
                          Store.i.removeRoute(r);
                        }),
                      ),
                    ),
                  ),
              ]),
      ),
      if (sel != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SwipeButton(
            title: 'Start the route',
            subtitle: '${sel.name} · ${fmtDistance(sel.meters)}',
            onDone: () => startTrip(context, to: sel.to, toName: sel.name.split(' → ').last),
          ),
        ),
    ]);
  }
}
