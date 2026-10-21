import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../data/store.dart';
import '../theme.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart' show openLink;
import '../widgets/signup.dart';
import 'map_screen.dart' show chooseOperators;

/// 3.10 Profile: account and settings, no side menu.
class ProfileScreen extends StatelessWidget {
  final AppState state;
  final ValueChanged<Place> onOpenPlace;
  final VoidCallback onOpenRoutes;
  const ProfileScreen({super.key, required this.state, required this.onOpenPlace, required this.onOpenRoutes});

  void _push(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, Store.i]),
      builder: (context, _) {
        final s = Store.i;
        return SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              SvgPicture.asset('assets/brand/logo_m.svg', width: 34, height: 34),
              const SizedBox(width: 8),
              const Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const Spacer(),
              // the round vehicle button opens My vehicle
              GestureDetector(
                onTap: () => _push(context, MyVehicleScreen(state: state)),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Image.asset((state.myVehicle ?? Vehicle.bike).asset),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text(state.hasAccount ? 'Your account' : 'Guest mode',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (!state.hasAccount)
                TextButton(onPressed: () => showSignupInvite(context, state), child: const Text('Create account')),
            ]),
            const SizedBox(height: 8),
            _group([
              _row(Icons.pedal_bike, state.myVehicle == null ? 'My vehicle' : '${state.myVehicle!.label}${state.model.isEmpty ? '' : ' · ${state.model}'}',
                  () => _push(context, MyVehicleScreen(state: state))),
              _row(Icons.favorite_border, 'Saved places', () => _push(context, SavedPlacesScreen(onOpen: onOpenPlace)),
                  trailing: '${s.savedPlaces.length}'),
              _row(Icons.route, 'Saved routes', onOpenRoutes, trailing: '${s.savedRoutes.length}'),
              _row(Icons.layers_outlined, 'What appears on the map', () => _push(context, const MapSettingsScreen())),
              _row(Icons.sync_alt, 'Sharing · ${s.operators.join(', ')}', () => chooseOperators(context)),
            ]),
            const SizedBox(height: 12),
            _group([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  const Icon(Icons.brightness_6_outlined),
                  const SizedBox(width: 16),
                  const Expanded(child: Text('Appearance')),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('Day')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Night')),
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                    ],
                    selected: {s.theme},
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    onSelectionChanged: (v) => s.setTheme(v.first),
                  ),
                ]),
              ),
              _row(Icons.notifications_none, 'Notifications', () => _push(context, const NotificationsScreen())),
              _row(Icons.shield_outlined, 'Anti-theft & Insurance', () => _push(context, const AntiTheftScreen())),
              _row(Icons.lightbulb_outline, 'Help · Replay the guide', state.replayGuide,
                  trailing: state.guideDone ? null : 'on the Map tab'),
            ]),
            const SizedBox(height: 12),
            const _DonateCard(),
            const SizedBox(height: 12),
            _group([
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset demo (start as a new user)'),
                subtitle: Text('App opens counted: ${state.opens}'),
                onTap: state.resetDemo,
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _group(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: rows),
      );

  Widget _row(IconData i, String t, VoidCallback onTap, {String? trailing}) => ListTile(
        leading: Icon(i),
        title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing != null) Text(trailing, style: const TextStyle(color: AppColors.soft)),
          const Icon(Icons.chevron_right),
        ]),
        onTap: onTap,
      );
}

class _DonateCard extends StatefulWidget {
  const _DonateCard();
  @override
  State<_DonateCard> createState() => _DonateCardState();
}

class _DonateCardState extends State<_DonateCard> {
  final _amount = TextEditingController(text: '10');
  bool _next = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your support matters', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 8),
        if (_next)
          Text(
            'Donation of \$${_amount.text}: payment opens in the secure window of the payment processor '
            '(added with the account features in milestone M6). The app never stores card details.',
            style: const TextStyle(color: AppColors.soft),
          )
        else
          Row(children: [
            const Text('♥ Donate', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.red)),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(prefixText: '\$ ', counterText: '', isDense: true),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => setState(() => _next = true),
              style: FilledButton.styleFrom(minimumSize: const Size(80, 44)),
              child: const Text('Next ›'),
            ),
          ]),
      ]),
    );
  }
}

// ───────────────────────── My vehicle ─────────────────────────

class MyVehicleScreen extends StatefulWidget {
  final AppState state;
  const MyVehicleScreen({super.key, required this.state});
  @override
  State<MyVehicleScreen> createState() => _MyVehicleScreenState();
}

class _MyVehicleScreenState extends State<MyVehicleScreen> {
  late Vehicle _v = widget.state.myVehicle ?? Vehicle.bike;
  late final _model = TextEditingController(text: widget.state.model);
  final _serial = TextEditingController();
  final Set<String> _opts = {};

  static const _options = {
    Vehicle.bike: ['E-bike', 'Cargo 2 seats', 'Cargo delivery', 'Cargo box', 'Trailer'],
    Vehicle.ebike: ['Cargo 2 seats', 'Cargo delivery', 'Cargo box', 'Trailer'],
    Vehicle.scooter: ['Cargo · basket'],
    Vehicle.moped: ['Cargo · delivery'],
    Vehicle.moto: ['Top box', 'Side bags'],
  };

  @override
  void dispose() {
    _model.dispose();
    _serial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('My vehicle')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Choose what you ride. The circle appears in Profile.', style: TextStyle(color: AppColors.soft)),
        const SizedBox(height: 12),
        Row(children: [
          for (final v in const [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _v = v;
                  _opts.clear();
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _v == v ? AppColors.slateTint : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _v == v ? AppColors.primary : Colors.transparent, width: 2),
                  ),
                  child: Column(children: [
                    SizedBox(height: 44, child: Image.asset(v.asset)),
                    const SizedBox(height: 4),
                    Text(v.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: const InputDecoration(
            hintText: 'Model, e.g. Trek FX 2',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _serial,
          decoration: const InputDecoration(
            hintText: 'Serial number',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Text('For the ${_v.label.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in _options[_v]!)
            FilterChip(
              label: Text(o),
              selected: _opts.contains(o),
              onSelected: (on) => setState(() {
                if (on) {
                  _opts.add(o);
                } else {
                  _opts.remove(o);
                }
              }),
            ),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () async {
            final v = _v == Vehicle.bike && _opts.contains('E-bike') ? Vehicle.ebike : _v;
            await widget.state.saveVehicle(v, _model.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

// ───────────────────────── Saved places ─────────────────────────

class SavedPlacesScreen extends StatefulWidget {
  final ValueChanged<Place> onOpen;
  const SavedPlacesScreen({super.key, required this.onOpen});
  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = Store.i.savedPlaceData.values
        .where((p) => p.address.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Saved places')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
            hintText: 'Search saved…',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Tap ♡ in a place sheet to save it here.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.soft)),
          ),
        for (final p in list)
          Card(
            elevation: 0,
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              Container(width: 6, height: 64, color: colorsFor(p.shownStatus).main),
              Expanded(
                child: ListTile(
                  leading: Glyph(p.type, size: 24, color: colorsFor(p.shownStatus).dark),
                  title: Text(p.address, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${p.type.title} · ${p.distance}'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpen(p);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.favorite, color: AppColors.red),
                    onPressed: () => setState(() => Store.i.toggleSaved(p)),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ───────────────────────── What appears on the map ─────────────────────────

class MapSettingsScreen extends StatelessWidget {
  const MapSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = Store.i;
        final all = s.showOnMap.values.every((v) => v);
        return Scaffold(
          backgroundColor: AppColors.paper,
          appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('What appears on the map')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Map', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Road', label: Text('Road')),
                ButtonSegment(value: 'Satellite', label: Text('Satellite')),
                ButtonSegment(value: 'Traffic', label: Text('Traffic'), enabled: false),
              ],
              selected: {s.satellite ? 'Satellite' : 'Road'},
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.setSatellite(v.first == 'Satellite'),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Day')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Night')),
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
              ],
              selected: {s.theme},
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.setTheme(v.first),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: SwitchListTile(
                value: s.parkNearDest,
                onChanged: s.setParkNearDest,
                secondary: const Icon(Icons.local_parking),
                title: const Text('Suggest bike parking near a searched address'),
                subtitle: const Text('A rack within 300 m is shown with a dotted walking line'),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Points of interest', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                SwitchListTile(value: all, onChanged: s.setAllShown, title: const Text('All', style: TextStyle(fontWeight: FontWeight.w800))),
                for (final t in PlaceType.values)
                  if (t != PlaceType.bmx)
                    SwitchListTile(
                      value: s.showOnMap[t] ?? true,
                      onChanged: (v) => s.setShow(t, v),
                      secondary: Glyph(t, size: 22, color: AppColors.primary),
                      title: Text(t.title),
                    ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ───────────────────────── Notifications ─────────────────────────

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const groups = {
      'Safety': ['SOS nearby', 'Theft alert in your area'],
      'Requests and bookings': ['Service reply', 'Rent / sharing booking'],
      'Community': ['Ride with Friends', 'Marketplace', 'Rain on a saved route'],
    };
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Notifications')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final g in groups.entries) ...[
            Text(g.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                for (final k in g.value)
                  SwitchListTile(
                    value: Store.i.notifications[k] ?? false,
                    onChanged: (v) => Store.i.setNotification(k, v),
                    title: Text(k),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ───────────────────────── Anti-theft & Insurance ─────────────────────────

class AntiTheftScreen extends StatefulWidget {
  const AntiTheftScreen({super.key});
  @override
  State<AntiTheftScreen> createState() => _AntiTheftScreenState();
}

class _AntiTheftScreenState extends State<AntiTheftScreen> {
  String _seg = 'Personal';
  bool _alert = false;
  final Map<String, int> _vote = {};

  static const _insurers = {
    'Personal': [
      ('Windy City Cycle Cover', '210 W Madison St, Chicago', '(312) 555-0141', 242, 11),
      ('Lakeshore Mobility Insurance', '88 E Randolph St, Chicago', '(312) 555-0187', 114, 6),
    ],
    'Delivery & Cargo': [
      ('Courier Shield', '400 N Wells St, Chicago', '(312) 555-0163', 87, 4),
      ('Cargo Ride Protect', '1200 S Canal St, Chicago', '(312) 555-0110', 52, 3),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Anti-theft & Insurance')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _alert ? AppColors.redTint : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _alert ? AppColors.red : Colors.transparent, width: 1.5),
          ),
          child: Row(children: [
            const Text('🚨', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Theft alert', style: TextStyle(fontWeight: FontWeight.w900)),
                Text(
                  _alert
                      ? 'Alert sent to riders nearby · last location ${userPos.latitude.toStringAsFixed(4)}, ${userPos.longitude.toStringAsFixed(4)}'
                      : 'If your vehicle is stolen, tell riders nearby with its last location.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.soft),
                ),
              ]),
            ),
            Switch(value: _alert, onChanged: (v) => setState(() => _alert = v)),
          ]),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Personal', label: Text('Personal')),
            ButtonSegment(value: 'Delivery & Cargo', label: Text('Delivery & Cargo')),
          ],
          selected: {_seg},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _seg = v.first),
        ),
        const SizedBox(height: 10),
        const Text('Insurers in your area', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (name, addr, phone, likes, dislikes) in _insurers[_seg]!)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(addr, style: const TextStyle(color: AppColors.soft, fontSize: 12.5)),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: () => openLink('tel:${phone.replaceAll(RegExp(r'[^0-9]'), '')}'),
                  icon: const Icon(Icons.phone_outlined, size: 16),
                  label: Text(phone),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, shape: const StadiumBorder()),
                ),
                const Spacer(),
                _thumb(name, 1, likes, Icons.thumb_up_alt_outlined, AppColors.green),
                const SizedBox(width: 10),
                _thumb(name, -1, dislikes, Icons.thumb_down_alt_outlined, AppColors.red),
              ]),
            ]),
          ),
        const Text('Only insurers in your area are shown. Demo names.',
            style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ]),
    );
  }

  Widget _thumb(String name, int v, int count, IconData icon, Color c) {
    final on = _vote[name] == v;
    return GestureDetector(
      onTap: () => setState(() {
        if (on) {
          _vote.remove(name);
        } else {
          _vote[name] = v;
        }
      }),
      child: Row(children: [
        Icon(icon, size: 20, color: on ? c : AppColors.soft),
        const SizedBox(width: 4),
        Text('${count + (on ? 1 : 0)}', style: TextStyle(fontWeight: FontWeight.w800, color: on ? c : AppColors.ink)),
      ]),
    );
  }
}
