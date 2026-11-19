import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../data/location.dart';
import '../data/places.dart';
import '../data/routing.dart';
import '../data/store.dart';
import '../data/trails.dart';
import '../theme.dart';
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
    _wait = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _busy = true);
      final r = await searchUs(q, near: userPos);
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

// ───────────────────────── Explore (manual 4.1) ─────────────────────────

const _trailColor = {'bicycle': AppColors.blue, 'mtb': Color(0xFFC98A00), 'motorcycle': Color(0xFF7A4FD0)};
Color trailColor(Trail t) => _trailColor[t.kind] ?? AppColors.blue;

/// Real routes near the rider: parks, forests, cities, OpenStreetMap. 10 free, then $1 a route.
class ExploreView extends StatefulWidget {
  const ExploreView({super.key});
  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  List<Trail>? _all; // null: still looking
  String _kind = 'All';
  String _length = 'Any length';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await TrailPass.i.load();
    final l = await Trails.i.near(userPos);
    if (mounted) setState(() => _all = l);
  }

  bool _fits(Trail t) {
    if (_kind == 'Bike' && t.kind != 'bicycle') return false;
    if (_kind == 'MTB' && t.kind != 'mtb') return false;
    if (_kind == 'Moto' && t.kind != 'motorcycle') return false;
    final mi = t.miles;
    return switch (_length) {
      '< 5 mi' => mi < 5,
      '5–15 mi' => mi >= 5 && mi <= 15,
      '15+ mi' => mi > 15,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final list = all == null ? const <Trail>[] : all.where(_fits).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final k in const ['All', 'Bike', 'MTB', 'Moto'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _length = v),
            itemBuilder: (_) => [
              for (final v in const ['Any length', '< 5 mi', '5–15 mi', '15+ mi']) PopupMenuItem(value: v, child: Text(v)),
            ],
            child: Chip(label: Text(_length == 'Any length' ? 'Length' : _length), avatar: const Icon(Icons.straighten, size: 16)),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 2), child: _FreeDots(left: TrailPass.i.freeLeft)),
      Expanded(
        child: all == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No routes near you match these filters.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.soft)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _card(list[i]),
                  ),
      ),
    ]);
  }

  Widget _card(Trail t) {
    final owned = TrailPass.i.owns(t.id);
    final badge = owned
        ? _Badge('Yours', AppColors.greenTint, AppColors.greenDark)
        : TrailPass.i.freeLeft > 0
            ? _Badge('Free', AppColors.greenTint, AppColors.greenDark)
            : _Badge(TrailPass.price, AppColors.yellowTint, AppColors.yellowDark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExploreDetail(trail: t)));
            if (mounted) setState(() {}); // free routes left may have changed
          },
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 58,
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE4EEE2), Color(0xFFD6E6EE)])),
                  child: CustomPaint(painter: _TrailShape(t, trailColor(t))),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text('${t.kindLabel} · ${t.milesText} · ${t.timeText}',
                        style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    if (t.operator != null)
                      Text(t.operator!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
                  ]),
                ),
                badge,
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _Badge(this.text, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
      );
}

/// "Free routes ●●○○○○○○○○ 8 left": full = used, empty = still free.
class _FreeDots extends StatelessWidget {
  final int left;
  const _FreeDots({required this.left});
  @override
  Widget build(BuildContext context) {
    final used = TrailPass.freeCount - left;
    return Row(children: [
      const Text('Free routes', style: TextStyle(color: AppColors.soft, fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(width: 10),
      for (int i = 0; i < TrailPass.freeCount; i++)
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < used ? AppColors.greenDark : null,
            border: i < used ? null : Border.all(color: AppColors.grey, width: 1.5),
          ),
        ),
      const Spacer(),
      Text(left == 0 ? 'all used' : '$left left',
          style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w700, fontSize: 12)),
    ]);
  }
}

/// The route's real shape, drawn from its line.
class _TrailShape extends CustomPainter {
  final Trail t;
  final Color color;
  _TrailShape(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = t.points;
    if (pts.length < 2) return;
    double x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    final k = math.cos(pts.first.latitude * math.pi / 180);
    for (final p in pts) {
      x0 = math.min(x0, p.longitude * k);
      x1 = math.max(x1, p.longitude * k);
      y0 = math.min(y0, p.latitude);
      y1 = math.max(y1, p.latitude);
    }
    const pad = 6.0;
    final sc = math.min((size.width - 2 * pad) / math.max(x1 - x0, 1e-9), (size.height - 2 * pad) / math.max(y1 - y0, 1e-9));
    final ox = (size.width - (x1 - x0) * sc) / 2, oy = (size.height - (y1 - y0) * sc) / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final l in t.lines) {
      final path = Path();
      for (final (i, p) in l.indexed) {
        final o = Offset(ox + (p.longitude * k - x0) * sc, size.height - oy - (p.latitude - y0) * sc);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TrailShape old) => old.t.id != t.id;
}

class ExploreDetail extends StatefulWidget {
  final Trail trail;
  const ExploreDetail({super.key, required this.trail});
  @override
  State<ExploreDetail> createState() => _ExploreDetailState();
}

class _ExploreDetailState extends State<ExploreDetail> {
  final _map = MapController();
  bool _ready = false, _busy = false;
  String? _problem;

  void _fit() {
    if (!_ready) return;
    _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(widget.trail.points), padding: const EdgeInsets.fromLTRB(30, 70, 30, 30)));
  }

  /// GO: the way to the nearest end of the route, then the route itself.
  Future<void> _go() async {
    final t = widget.trail;
    setState(() {
      _busy = true;
      _problem = null;
    });
    const d = Distance();
    final fromEnd = d(userPos, t.end) < d(userPos, t.start);
    final line = fromEnd ? t.points.reversed.toList() : t.points;
    double len = 0;
    for (int i = 1; i < line.length; i++) {
      len += d(line[i - 1], line[i]);
    }
    final trailSec = t.minutes * 60;
    RouteResult? toStart;
    if (d(userPos, line.first) > 150) toStart = await bikeRoute([userPos, line.first]);
    if (!mounted) return;
    final steps = [
      ...?toStart?.steps,
      RouteStep('Follow ${t.name}', t.name, len, line.first),
    ];
    final r = RouteResult([...?toStart?.points, ...line], (toStart?.meters ?? 0) + len, (toStart?.seconds ?? 0) + trailSec, steps,
        label: 'Route');
    setState(() => _busy = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GuidanceScreen(route: r, to: line.last, toName: t.name, vehicle: t.kind == 'motorcycle' ? 'moto' : 'bike'),
    ));
  }

  Future<void> _main() async {
    final t = widget.trail;
    final pass = TrailPass.i;
    if (pass.owns(t.id) || await pass.takeFree(t.id)) {
      await _go();
      return;
    }
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Unlock ${t.name}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Your 10 free routes are used. This route stays yours after you pay, and appears in Saved.',
                style: TextStyle(color: AppColors.soft)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue, minimumSize: const Size.fromHeight(48)),
              child: const Text('Pay ${TrailPass.price}', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await pass.buy(t.id);
    _saveRoute();
    await _go();
  }

  void _saveRoute() {
    final t = widget.trail;
    if (Store.i.savedRoutes.any((s) => s.name == t.name)) return;
    Store.i.saveRoute(SavedRoute(t.name, t.start, t.end, t.km * 1000, t.minutes * 60));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trail;
    final pass = TrailPass.i;
    final owned = pass.owns(t.id);
    final web = t.website == null ? null : Uri.tryParse(t.website!.startsWith('http') ? t.website! : 'https://${t.website}');
    final note = owned
        ? null
        : pass.freeLeft > 0
            ? ('Uses 1 of your 10 free routes · ${pass.freeLeft} left', AppColors.greenDark)
            : ('Your 10 free routes are used', AppColors.yellowDark);
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(children: [
        Positioned.fill(
          bottom: 250,
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: t.start,
              initialZoom: 12,
              onMapReady: () {
                _ready = true;
                _fit();
              },
            ),
            children: [
              baseTiles(),
              PolylineLayer(polylines: [
                for (final l in t.lines) Polyline(points: l, strokeWidth: 8, color: Colors.white),
                for (final l in t.lines) Polyline(points: l, strokeWidth: 5, color: trailColor(t)),
              ]),
            ],
          ),
        ),
        Positioned(
          left: 12,
          top: MediaQuery.of(context).padding.top + 8,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + MediaQuery.of(context).padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                    width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              Text(t.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              if (t.fromTo != null || t.operator != null)
                Text(t.fromTo ?? t.operator!, style: const TextStyle(color: AppColors.soft, fontSize: 12.5)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FactTile(t.milesText, 'distance')),
                const SizedBox(width: 6),
                Expanded(child: FactTile(t.timeText, 'time')),
                const SizedBox(width: 6),
                Expanded(child: FactTile(t.kindLabel, 'route')),
              ]),
              const SizedBox(height: 8),
              if (t.operator != null || web != null)
                InkWell(
                  onTap: web == null ? null : () => launchUrl(web, mode: LaunchMode.externalApplication),
                  child: Text(
                    [if (t.operator != null) t.operator!, if (web != null) web.host.replaceFirst('www.', '')].join(' · '),
                    style: TextStyle(color: web == null ? AppColors.grey : AppColors.blue, fontSize: 12),
                  ),
                ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(note.$1, style: TextStyle(color: note.$2, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ],
              if (_problem != null) Text(_problem!, style: const TextStyle(color: AppColors.redDark)),
              const SizedBox(height: 10),
              Row(children: [
                IconButton.outlined(onPressed: _fit, icon: const Icon(Icons.map_outlined), tooltip: 'Show the route'),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _main,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.blue, minimumSize: const Size.fromHeight(48)),
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : (owned || pass.freeLeft > 0 ? const Icon(Icons.navigation) : const SizedBox.shrink()),
                    label: Text(
                      owned ? 'GO' : (pass.freeLeft > 0 ? 'GO · free route' : 'Unlock for ${TrailPass.price}'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
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
