import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/app_state.dart';
import '../data/osm.dart' show etaMinutes;
import '../data/place_photos.dart';
import '../data/places.dart';
import '../data/ride_classes.dart';
import '../data/ride_parks.dart';
import '../theme.dart';
import '../widgets/class_note.dart';
import '../widgets/pin.dart' show UserDot;
import '../widgets/place_sheet.dart' show openLink;
import '../widgets/signup.dart';
import '../widgets/tiles.dart';
import 'trip_screen.dart';

/// Community: Marketplace · Ride with Friends · BMX.
class CommunityScreen extends StatefulWidget {
  final AppState state;
  const CommunityScreen({super.key, required this.state});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String _seg = 'Marketplace';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Community', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Marketplace', label: Text('Marketplace')),
              ButtonSegment(value: 'Ride', label: Text('Ride')),
              ButtonSegment(value: 'BMX', label: Text('BMX')),
            ],
            selected: {_seg},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (_seg) {
            'Marketplace' => MarketplaceView(state: widget.state),
            'Ride' => const RideHome(),
            _ => const BmxMap(),
          },
        ),
      ]),
    );
  }
}

// ───────────────────────── Marketplace ─────────────────────────

class Listing {
  final String title, description, author, when, distance;
  final String? price;
  final String? image; // asset
  final IconData icon;
  final String category;
  const Listing(this.title, this.description, this.price, this.author, this.when, this.distance, this.category,
      {this.image, this.icon = Icons.pedal_bike});
}

final List<Listing> _listings = [
  const Listing('Trek FX 2 hybrid, size M', 'Light hybrid, new tires, serviced last month.', '\$450', 'Alex', '3 h ago',
      '1.2 km', 'Bikes',
      image: 'assets/vehicles/bike.png'),
  const Listing('Urban helmet M', 'Worn twice, with rear light.', '\$35', 'Maria', '5 h ago', '0.8 km', 'Gear',
      icon: Icons.sports_motorsports_outlined),
  const Listing('Electric scooter 25 km range', 'Charger included. Small scratch on the deck.', '\$220', 'Dan',
      '1 day ago', '3.4 km', 'Scooters',
      image: 'assets/vehicles/scooter.png'),
  const Listing('U-lock + cable', 'Kryptonite, two keys.', '\$25', 'Ioana', '1 day ago', '2.1 km', 'Gear',
      icon: Icons.lock_outline),
  const Listing('E-bike, 500 Wh battery', 'Commuter e-bike, 1,800 km.', '\$1,150', 'Sam', '2 days ago', '4.0 km', 'Bikes',
      image: 'assets/vehicles/ebike.png'),
  const Listing('Moped 50cc', 'Runs great, papers in order.', '\$1,900', 'Chris', '3 days ago', '6.2 km', 'Mopeds',
      image: 'assets/vehicles/moped.png'),
  const Listing('Kids bike 16"', 'Free to a good home.', null, 'Lena', '4 days ago', '1.9 km', 'Bikes',
      icon: Icons.child_care),
];

class MarketplaceView extends StatefulWidget {
  final AppState state;
  const MarketplaceView({super.key, required this.state});
  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView> {
  String _cat = 'All';

  Future<void> _post() async {
    if (!widget.state.hasAccount) {
      await showSignupInvite(context, widget.state);
      if (!widget.state.hasAccount || !mounted) return;
    }
    final l = await Navigator.of(context).push<Listing>(MaterialPageRoute(builder: (_) => const PostListing()));
    if (l != null && mounted) setState(() => _listings.insert(0, l));
  }

  @override
  Widget build(BuildContext context) {
    final list = _cat == 'All' ? _listings : _listings.where((l) => l.category == _cat).toList();
    return Stack(children: [
      Column(children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final c in const ['All', 'Bikes', 'Scooters', 'Mopeds', 'Gear'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
              ),
          ]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.74,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _ListingCard(
              list[i],
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ListingDetail(listing: list[i]))),
            ),
          ),
        ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: _post,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}

Widget _listingImage(Listing l, {double radius = 14}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: AppColors.paper,
        alignment: Alignment.center,
        child: l.image != null
            ? Padding(padding: const EdgeInsets.all(10), child: Image.asset(l.image!, fit: BoxFit.contain))
            : Icon(l.icon, size: 54, color: AppColors.slate),
      ),
    );

class _ListingCard extends StatelessWidget {
  final Listing l;
  final VoidCallback onTap;
  const _ListingCard(this.l, {required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SizedBox(width: double.infinity, child: _listingImage(l))),
              const SizedBox(height: 8),
              Text(l.price ?? 'Free',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: l.price == null ? AppColors.greenDark : AppColors.ink)),
              Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${l.author} · ${l.when} · ${l.distance}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
            ]),
          ),
        ),
      );
}

class ListingDetail extends StatefulWidget {
  final Listing listing;
  const ListingDetail({super.key, required this.listing});
  @override
  State<ListingDetail> createState() => _ListingDetailState();
}

class _ListingDetailState extends State<ListingDetail> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.paper),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(height: 230, child: _listingImage(l, radius: 20)),
        const SizedBox(height: 14),
        Text(l.price ?? 'Free', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text(l.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${l.author} · ${l.when} · ${l.distance} away', style: const TextStyle(color: AppColors.soft)),
        const SizedBox(height: 14),
        Text(l.description, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.chat_outlined), label: const Text('Message seller')),
        const SizedBox(height: 4),
        const Text('Opens phone or WhatsApp. Never pay before you see the item.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _reported ? null : () => setState(() => _reported = true),
          icon: Icon(_reported ? Icons.check : Icons.flag_outlined, color: AppColors.red),
          label: Text(_reported ? 'Reported · thank you' : 'Report listing', style: const TextStyle(color: AppColors.red)),
        ),
      ]),
    );
  }
}

class PostListing extends StatefulWidget {
  const PostListing({super.key});
  @override
  State<PostListing> createState() => _PostListingState();
}

class _PostListingState extends State<PostListing> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  bool _photo = false;
  String _cat = 'Bikes';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  bool get _ok => _photo && _title.text.trim().isNotEmpty && _desc.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String h) => InputDecoration(
          hintText: h,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
        );
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('New listing')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: () => setState(() => _photo = !_photo),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: _photo ? AppColors.greenTint : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _photo ? AppColors.green : AppColors.line, width: 1.5),
            ),
            alignment: Alignment.center,
            child: _photo
                ? Image.asset('assets/vehicles/bike.png', height: 110)
                : const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_a_photo_outlined, size: 34, color: AppColors.slate),
                    SizedBox(height: 6),
                    Text('Add a photo (required)', style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _title, onChanged: (_) => setState(() {}), decoration: deco('Title (required)')),
        const SizedBox(height: 8),
        TextField(
            controller: _desc,
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            decoration: deco('Description (required)')),
        const SizedBox(height: 8),
        TextField(controller: _price, keyboardType: TextInputType.number, decoration: deco('Price in \$ (optional)')),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final c in const ['Bikes', 'Scooters', 'Mopeds', 'Gear'])
            ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _ok
              ? () => Navigator.pop(
                    context,
                    Listing(
                      _title.text.trim(),
                      _desc.text.trim(),
                      _price.text.trim().isEmpty ? null : '\$${_price.text.trim()}',
                      'You',
                      'just now',
                      '0 km',
                      _cat,
                      image: 'assets/vehicles/bike.png',
                    ),
                  )
              : null,
          child: const Text('Post'),
        ),
        const SizedBox(height: 6),
        const Text('The listing appears after the photo check. It expires in 30 days.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ]),
    );
  }
}

// ───────────────────────── Ride with Friends ─────────────────────────

const _rideColors = [Color(0xFF2F6FDC), Color(0xFF5D9A30), Color(0xFFE9A800), Color(0xFFE0484D)];

class Rider {
  final int n;
  final String name;
  final bool host;
  bool joined;
  Rider(this.n, this.name, {this.host = false, this.joined = true});
}

class RideHome extends StatefulWidget {
  const RideHome({super.key});
  @override
  State<RideHome> createState() => _RideHomeState();
}

class _RideHomeState extends State<RideHome> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _create() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RideLobby(host: true)));

  void _join() {
    final c = _code.text.trim().toUpperCase();
    if (c.replaceAll('RWF-', '').length != 4) {
      setState(() => _error = 'Codes look like RWF-4821');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RideLobby(host: false)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _create,
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Row(children: [
              Icon(Icons.groups_2_outlined, color: Colors.white, size: 40),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Create a Ride', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('Pick a route, share the QR, everyone sees the group live.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Join a Ride', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Scan the host’s QR or type the code. No account needed, just a name.',
              style: TextStyle(fontSize: 12.5, color: AppColors.soft)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RideLobby(host: false))),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: const StadiumBorder()),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'RWF-4821',
                  errorText: _error,
                  filled: true,
                  fillColor: AppColors.paper,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _join,
              style: FilledButton.styleFrom(minimumSize: const Size(84, 52)),
              child: const Text('Join'),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('Your location is visible only to the group and only while the Ride is active.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
    ]);
  }
}

class RideLobby extends StatefulWidget {
  final bool host;
  const RideLobby({super.key, required this.host});
  @override
  State<RideLobby> createState() => _RideLobbyState();
}

class _RideLobbyState extends State<RideLobby> {
  static const code = 'RWF-4821';
  late final List<Rider> _riders = widget.host
      ? [Rider(1, 'You', host: true), Rider(2, 'Maria'), Rider(3, 'Ioana', joined: false)]
      : [Rider(1, 'Andrei', host: true), Rider(2, 'Maria'), Rider(3, 'You')];
  final List<Timer> _timers = [];
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _timers.add(Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _riders[2].joined = true);
    }));
    _timers.add(Timer(const Duration(seconds: 4), () {
      if (mounted && !_locked) setState(() => _riders.add(Rider(4, 'Dan')));
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Saturday in the park')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.yellowTint, borderRadius: BorderRadius.circular(12)),
            child: Text(widget.host ? 'HOST ★ · you' : 'Host: Andrei ★',
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.yellowDark)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: QrImageView(data: 'https://mobility.app/ride/$code?t=demo', size: 190, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(code, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3)),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.ios_share), label: const Text('Share link')),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            for (final r in _riders)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: _rideColors[(r.n - 1) % 4],
                  child: Text('${r.n}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
                title: Text('${r.name}${r.host ? ' ★' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(r.joined ? 'ready' : 'joining…'),
                trailing: widget.host && !r.host
                    ? IconButton(
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => setState(() => _riders.remove(r)),
                      )
                    : null,
              ),
          ]),
        ),
        if (widget.host)
          SwitchListTile(
            value: _locked,
            onChanged: (v) => setState(() => _locked = v),
            title: const Text('Lock new joins'),
          ),
        const SizedBox(height: 10),
        if (widget.host)
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => RideLive(riders: _riders.where((r) => r.joined).toList()))),
            child: const Text('Start Ride'),
          )
        else
          const Center(child: Text('Waiting for the host to start…', style: TextStyle(color: AppColors.soft))),
      ]),
    );
  }
}

const _route = [
  LatLng(41.8885, -87.6145),
  LatLng(41.8960, -87.6175),
  LatLng(41.9030, -87.6230),
  LatLng(41.9100, -87.6262),
  LatLng(41.9170, -87.6300),
  LatLng(41.9240, -87.6330),
  LatLng(41.9300, -87.6352),
];

LatLng _along(double t) {
  t = t.clamp(0.0, 1.0).toDouble();
  final f = t * (_route.length - 1);
  final i = f.floor().clamp(0, _route.length - 2);
  final k = f - i;
  final a = _route[i], b = _route[i + 1];
  return LatLng(a.latitude + (b.latitude - a.latitude) * k, a.longitude + (b.longitude - a.longitude) * k);
}

class RideLive extends StatefulWidget {
  final List<Rider> riders;
  const RideLive({super.key, required this.riders});
  @override
  State<RideLive> createState() => _RideLiveState();
}

class _RideLiveState extends State<RideLive> {
  late final List<double> _t = [for (int i = 0; i < widget.riders.length; i++) 0.04 - i * 0.012];
  late final List<double> _speed = [for (int i = 0; i < widget.riders.length; i++) 24.0 - i * (i == 3 ? 3.4 : 2.0)];
  Timer? _tick;
  String? _sent;
  Timer? _sentTimer;

  @override
  void initState() {
    super.initState();
    final r = math.Random(4);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _t.length; i++) {
          _speed[i] = (_speed[i] + (r.nextDouble() - 0.5) * 1.6).clamp(10.0, 30.0).toDouble();
          _t[i] = math.min(1.0, _t[i] + _speed[i] / 3600 / 5.5 * 6); // demo runs ~6x faster
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sentTimer?.cancel();
    super.dispose();
  }

  void _send(String what) {
    _sentTimer?.cancel();
    setState(() => _sent = what);
    _sentTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _sent = null);
    });
  }

  void _end() {
    final order = List.generate(widget.riders.length, (i) => i)..sort((a, b) => _t[b].compareTo(_t[a]));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ride finished'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (pos, i) in order.indexed)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: _rideColors[i % 4],
                child: Text('${widget.riders[i].n}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text('${pos + 1}. ${widget.riders[i].name}'),
              subtitle: Text('${_speed[i].toStringAsFixed(1)} km/h avg · score ${(70 + _speed[i]).round()}'),
            ),
        ]),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lead = _t.reduce(math.max);
    final behind = [for (int i = 0; i < _t.length; i++) if (lead - _t[i] > 0.05) i];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text('Group · ${widget.riders.length}'),
        actions: [TextButton(onPressed: _end, child: const Text('End', style: TextStyle(color: AppColors.red)))],
      ),
      body: Column(children: [
        Expanded(
          child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(41.9090, -87.6250), initialZoom: 13.6),
            children: [
              baseTiles(),
              PolylineLayer(polylines: [
                Polyline(points: _route, strokeWidth: 6, color: AppColors.blue.withValues(alpha: 0.85)),
              ]),
              MarkerLayer(markers: [
                for (int i = 0; i < widget.riders.length; i++)
                  Marker(
                    point: _along(_t[i]),
                    width: 34,
                    height: 34,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _rideColors[i % 4],
                        shape: BoxShape.circle,
                        border: Border.all(color: behind.contains(i) ? AppColors.red : Colors.white, width: 3),
                      ),
                      alignment: Alignment.center,
                      child: Text('${widget.riders[i].n}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('Group live', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              if (behind.isNotEmpty)
                Text('${behind.map((i) => widget.riders[i].n).join(', ')} falling behind',
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (int i = 0; i < widget.riders.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: behind.contains(i) ? AppColors.redTint : AppColors.paper,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                      '${widget.riders[i].n}${widget.riders[i].host ? '★' : ''} ${widget.riders[i].name} · ${_speed[i].round()} km/h',
                      style: TextStyle(fontWeight: FontWeight.w700, color: _rideColors[i % 4])),
                ),
            ]),
            const SizedBox(height: 10),
            if (_sent != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('“$_sent” sent to the group',
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.greenDark)),
              ),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _send('Wait'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.ink),
                  child: const Text('Wait'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _send('Slow Down'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  child: const Text('Slow Down'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── BMX: kids & family spaces ─────────────────────────

/// The BMX page: every real BMX track, pump track, bike park and skatepark within 25 miles
/// (from OpenStreetMap), on a map centred on the rider.
class BmxMap extends StatefulWidget {
  const BmxMap({super.key});

  @override
  State<BmxMap> createState() => _BmxMapState();
}

class _BmxMapState extends State<BmxMap> {
  List<RidePark>? _parks; // null: still looking

  @override
  void initState() {
    super.initState();
    rideParks(userPos).then((l) {
      if (mounted) setState(() => _parks = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final parks = _parks ?? const <RidePark>[];
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: userPos, initialZoom: 11.2),
          children: [
            baseTiles(),
            MarkerLayer(markers: [
              Marker(point: userPos, width: 34, height: 34, child: const UserDot()),
              for (final b in parks)
                Marker(
                  point: b.pos,
                  width: 44,
                  height: 52,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                      builder: (_) => BmxSheet(place: b),
                    ),
                    child: const _BmxPin(),
                  ),
                ),
            ]),
          ],
        ),
        // one quiet line at the top: how many, or that we are still looking
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // our note: free classes for children where the rider is; a tap reads it, then the link
            ClassPill(classNear(userPos)),
            const SizedBox(height: 6),
            Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Text(
                _parks == null
                    ? 'Looking for parks near you…'
                    : parks.isEmpty
                        ? 'No parks found within 25 miles yet'
                        : '${parks.length} parks within 25 miles',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _BmxPin extends StatelessWidget {
  const _BmxPin();
  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.topCenter, children: [
        Transform.rotate(
          angle: -0.785398,
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFF3A4850),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),
        ),
        Positioned(
          top: 7,
          child: SvgPicture.asset(PlaceType.bmx.glyph,
              width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
        ),
      ]);
}

class BmxSheet extends StatefulWidget {
  final RidePark place;
  const BmxSheet({super.key, required this.place});
  @override
  State<BmxSheet> createState() => _BmxSheetState();
}

class _BmxSheetState extends State<BmxSheet> {
  List<PlacePhoto> _mine = const [], _online = const [];

  /// the park as a place, for the photo search (photos from 2024 on that look at it)
  late final Place _asPlace = Place(
    id: 'park/${widget.place.id}',
    type: PlaceType.bmx,
    address: widget.place.name,
    pos: widget.place.pos,
    status: Status.neutral,
    distance: '',
    etaMin: const {},
    osm: true,
  );

  void _loadMine() => MyPhotos.i.of(_asPlace.id).then((l) {
        if (mounted) setState(() => _mine = l);
      });

  @override
  void initState() {
    super.initState();
    MyPhotos.i.addListener(_loadMine);
    _loadMine();
    photosLookingAt(_asPlace).then((l) {
      if (mounted && l.isNotEmpty) setState(() => _online = l);
    });
  }

  @override
  void dispose() {
    MyPhotos.i.removeListener(_loadMine);
    super.dispose();
  }

  void _vote(int v) => setState(() {
        final b = widget.place;
        if (b.vote == 1) b.likes--;
        if (b.vote == -1) b.dislikes--;
        b.vote = b.vote == v ? 0 : v;
        if (b.vote == 1) b.likes++;
        if (b.vote == -1) b.dislikes++;
      });

  @override
  Widget build(BuildContext context) {
    final b = widget.place;
    final m = const Distance()(userPos, b.pos);
    final miles = (m / 1609.34).toStringAsFixed(1);
    final photos = [..._mine, for (final u in b.photos) PlacePhoto(u, 'map'), ..._online];
    Widget voteBtn(IconData icon, int count, int v, Color on) => OutlinedButton.icon(
          onPressed: () => _vote(v),
          icon: Icon(icon, size: 18, color: b.vote == v ? Colors.white : on),
          label: Text('$count', style: TextStyle(color: b.vote == v ? Colors.white : AppColors.ink)),
          style: OutlinedButton.styleFrom(
            backgroundColor: b.vote == v ? on : null,
            side: BorderSide(color: on.withValues(alpha: 0.6)),
            shape: const StadiumBorder(),
            minimumSize: const Size(70, 40),
          ),
        );

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.slateTint,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text([b.kind, if (b.address != null) b.address!].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.soft, fontSize: 12.5)),
              ]),
            ),
            FilledButton.icon(
              onPressed: () => startTrip(context, to: b.pos, toName: b.name),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Trip'),
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // who it is for: bikes named in the map data, or a skatepark where the sign decides
            Row(children: [
              Icon(b.bikes == true ? Icons.pedal_bike_rounded : Icons.info_outline_rounded,
                  size: 18, color: b.bikes == true ? AppColors.greenDark : AppColors.yellowDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(b.forWhom,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: b.bikes == true ? AppColors.greenDark : AppColors.yellowDark)),
              ),
            ]),
            if (b.facts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in b.facts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
                    child: Text(f, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
              ]),
            ],
            if (b.hours != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 18, color: AppColors.soft),
                const SizedBox(width: 6),
                Expanded(child: Text(b.hours!, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ],
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PageView.builder(
                    itemCount: photos.length,
                    itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
                      photos[i].local
                          ? Image.file(File(photos[i].url), fit: BoxFit.cover)
                          : RotatedBox(
                              quarterTurns: photos[i].turns,
                              child: Image.network(photos[i].url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      color: AppColors.paper,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.soft))),
                            ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              'Photo · ${i + 1}/${photos.length}${photos[i].credit == 'map' ? '' : ' · ${photos[i].credit}'}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              TextButton.icon(
                onPressed: () => MyPhotos.i.take(_asPlace.id),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(photos.isEmpty ? 'Add the first photo' : 'Add a photo'),
              ),
              const Spacer(),
              voteBtn(Icons.thumb_up_alt_outlined, b.likes, 1, AppColors.green),
              const SizedBox(width: 6),
              voteBtn(Icons.thumb_down_alt_outlined, b.dislikes, -1, AppColors.red),
            ]),
            if (b.phone != null || b.website != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                if (b.phone != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink('tel:${b.phone!.replaceAll(RegExp(r'[^0-9+]'), '')}'),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text(b.phone!),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, shape: const StadiumBorder()),
                  ),
                if (b.website != null)
                  OutlinedButton.icon(
                    onPressed: () => openLink(b.website!.startsWith('http') ? b.website! : 'https://${b.website}'),
                    icon: const Icon(Icons.public, size: 16),
                    label: const Text('Website'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, shape: const StadiumBorder()),
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            Text('$miles mi away · ${etaMinutes(m, Vehicle.bike)} min by bike',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Place data © OpenStreetMap contributors.', style: TextStyle(fontSize: 11, color: AppColors.soft)),
          ]),
        ),
      ]),
    );
  }
}
