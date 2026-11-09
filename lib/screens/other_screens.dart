import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../data/location.dart';
import '../data/store.dart';
import '../data/zones.dart';
import '../theme.dart';
import '../widgets/pin.dart';
import '../widgets/place_sheet.dart' show openLink;
import '../widgets/signup.dart';
import 'map_screen.dart' show chooseOperators;
import '../data/auth.dart';

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
            ]),
            const SizedBox(height: 6),
            _AccountCard(state: state),
            const SizedBox(height: 8),
            _group([
              _row(Icons.pedal_bike, state.myVehicle == null ? 'My vehicle' : '${state.myVehicle!.label}${state.model.isEmpty ? '' : ' · ${state.model}'}',
                  () => showVehicleStep(context, state, canClose: true)),
              _row(Icons.favorite_border, 'Saved places', () => _push(context, SavedPlacesScreen(onOpen: onOpenPlace)),
                  trailing: '${s.savedPlaces.length}'),
              _row(Icons.route, 'Saved routes', onOpenRoutes, trailing: '${s.savedRoutes.length}'),
              _row(Icons.public, 'My map areas', () => _push(context, const MyAreasScreen()),
                  trailing: '${s.zones.where((z) => z.active).length}'),
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
              ListTile(
                leading: const Icon(Icons.sos_outlined, color: AppColors.red),
                title: const Text('Test: an SOS from a rider nearby'),
                subtitle: const Text('Then open the Map tab'),
                onTap: () => Store.i.simulateIncomingSos(userPos),
              ),
            ]),
          ]),
        );
      },
    );
  }

  // a white card that list rows can paint their tap effect on (Material, not a plain box)
  Widget _group(List<Widget> rows) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
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
                ButtonSegment(value: 'Bike', label: Text('Bike map')),
                ButtonSegment(value: 'Satellite', label: Text('Satellite')),
              ],
              selected: {s.mapStyle},
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.setMapStyle(v.first),
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
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
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
              child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final k in g.value)
                  SwitchListTile(
                    value: Store.i.notifications[k] ?? false,
                    onChanged: (v) => Store.i.setNotification(k, v),
                    title: Text(k),
                  ),
              ]),
              ),
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


// ───────────────────────── My map areas ─────────────────────────

/// 2 free areas (100 miles each) where the rider lives, studies or works; others \$1 for 30 days.
class MyAreasScreen extends StatelessWidget {
  const MyAreasScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final s = Store.i;
          final free = s.freeZones;
          final paid = s.zones.where((z) => z.paid).toList();
          return Scaffold(
            backgroundColor: AppColors.paper,
            appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('My map areas')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Free · ${free.length} of ${MapZone.maxFree}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('They come by themselves where you are with GPS: home, school, work. '
                  '${MapZone.radiusMiles} miles around each, everything included.',
                  style: TextStyle(color: AppColors.soft, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final z in free) _card(context, z),
              if (free.length < MapZone.maxFree)
                _hint('Open the map where you live or work: the next free area is added there.'),
              const SizedBox(height: 18),
              const Text('Unlocked with ${MapZone.price}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('A trip or a holiday: ${MapZone.radiusMiles} miles for ${MapZone.passDays} days. '
                  'Move the map there and tap Unlock.',
                  style: TextStyle(color: AppColors.soft, fontSize: 12.5)),
              const SizedBox(height: 8),
              if (paid.isEmpty) _hint('None yet.'),
              for (final z in paid) _card(context, z),
            ]),
          );
        },
      );

  Widget _hint(String t) => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: const TextStyle(color: AppColors.soft)),
      );

  Widget _card(BuildContext context, MapZone z) {
    final s = Store.i;
    final sub = z.paid
        ? (z.active ? '${z.daysLeft} days left' : 'ended')
        : 'free · since ${z.added.month}/${z.added.day}/${z.added.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(z.paid ? Icons.confirmation_number_outlined : Icons.home_outlined,
            color: z.paid ? AppColors.yellowDark : AppColors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(z.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${MapZone.radiusMiles} miles · $sub', style: const TextStyle(fontSize: 12, color: AppColors.soft)),
          ]),
        ),
        if (!z.paid)
          TextButton(
            onPressed: s.canMove
                ? () async {
                    final n = await cityName(userPos) ?? 'My area';
                    s.moveFreeZone(z, userPos, n);
                  }
                : null,
            child: Text(s.canMove ? 'I moved here' : 'Move later'),
          ),
      ]),
    );
  }
}

/// Your account at the top of Profile: who you are and how you signed in, with Sign out;
/// as a guest, a Sign in button that opens our sign-in pop-up.
class _AccountCard extends StatelessWidget {
  final AppState state;
  const _AccountCard({required this.state});

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x550F1E24),
      builder: (c) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.logout_rounded, color: AppColors.red, size: 30),
            const SizedBox(height: 8),
            const Text('Sign out?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Your places, routes and vehicle stay saved in your account.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.soft)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                child: const Text('Sign out'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) await state.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = state.hasAccount;
    final name = Auth.i.name;
    final email = Auth.i.user?.email ?? Auth.i.user?.phoneNumber;
    final photo = Auth.i.photoUrl;
    final initial = (name ?? 'M').trim().isEmpty ? 'M' : (name ?? 'M').trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: signedIn ? AppColors.ink : AppColors.paper,
              image: signedIn && photo != null ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: signedIn
                ? (photo == null
                    ? Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))
                    : null)
                : const Icon(Icons.person_outline, color: AppColors.soft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(signedIn ? (name ?? 'Your account') : 'Guest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                signedIn
                    ? [if (email != null && email != name) email, if (Auth.i.provider != null) 'via ${Auth.i.provider}']
                        .join(' · ')
                    : 'Sign in to keep your places, routes and vehicle on any phone.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.soft),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: signedIn
              ? OutlinedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: Color(0xFFF1B4B6), width: 1.5),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : FilledButton(
                  onPressed: () => showSignupInvite(context, state),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Sign in'),
                ),
        ),
      ]),
    );
  }
}

