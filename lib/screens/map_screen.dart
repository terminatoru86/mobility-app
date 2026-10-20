import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../theme.dart';
import '../widgets/cluster.dart';
import '../widgets/guide.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart';
import '../widgets/signup.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
    super.dispose();
  }

  List<Place> get _visible =>
      _filter == null ? demoPlaces : demoPlaces.where((p) => p.type.group == _filter).toList();

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
    if (_zoom < 13.5) {
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
          child: PlacePin(place: p, selected: _selected == p.id, small: _zoom < 14.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: kUserPos,
          initialZoom: 15,
          minZoom: 10,
          maxZoom: 19,
          onPositionChanged: (camera, hasGesture) {
            if ((camera.zoom - _zoom).abs() > 0.05) setState(() => _zoom = camera.zoom);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mobility.app',
          ),
          MarkerLayer(markers: [
            const Marker(point: kUserPos, width: 34, height: 34, child: UserDot()),
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
        ]),
      ),
      Positioned(
        right: 14,
        bottom: 24,
        child: Column(children: [
          _roundBtn(_kLocate, Icons.my_location, Colors.white, AppColors.ink, () => _map.move(kUserPos, 15)),
          const SizedBox(height: 12),
          _roundBtn(_kReport, Icons.add, AppColors.primary, Colors.white, () {}),
        ]),
      ),
      Positioned(
        left: 14,
        bottom: 30,
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

  Widget _searchBar() => Container(
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
          const Expanded(child: Text('Search address', style: TextStyle(color: AppColors.soft, fontSize: 16))),
        ]),
      );

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
