import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth.dart';
import '../data/places.dart';
import '../data/shop_owner.dart';
import '../theme.dart';

/// Profile → Shop owner: the owner picks the shop on the map and fills its page.
class ShopOwnerScreen extends StatefulWidget {
  const ShopOwnerScreen({super.key});
  @override
  State<ShopOwnerScreen> createState() => _ShopOwnerScreenState();
}

bool _ownable(PlaceType t) => t == PlaceType.shop || t == PlaceType.service || t == PlaceType.rent || t == PlaceType.bmx;

class _ShopOwnerScreenState extends State<ShopOwnerScreen> {
  ShopPage? _page;
  Place? _place; // the shop on the map (when it is among the places we know)
  bool _loading = true, _saving = false, _sent = false;
  int _visits = 0;
  final _search = TextEditingController();
  final _email = TextEditingController(), _phone = TextEditingController(), _hours = TextEditingController();
  final _dText = TextEditingController(), _dOther = TextEditingController(), _msg = TextEditingController();
  late ShopPage _draft;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_search, _email, _phone, _hours, _dText, _dOther, _msg]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final mine = await ShopPages.i.mine();
    if (!mounted) return;
    if (mine.isNotEmpty) {
      _use(mine.first);
      _visits = await ShopPages.i.visitCount(mine.first.id);
      _sent = await ShopPages.i.sentThisMonth(mine.first.id);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _use(ShopPage p) {
    _page = p;
    _draft = p;
    _place = knownPlaces.where((x) => shopKey(x.id) == shopKey(p.id)).firstOrNull;
    _email.text = p.email;
    _phone.text = p.phone;
    _hours.text = p.hours;
    _dText.text = p.discountText;
    _dOther.text = p.discountOther;
  }

  List<Place> get _found {
    final q = _search.text.trim().toLowerCase();
    if (q.length < 2) return const [];
    return knownPlaces
        .where((p) =>
            p.osm &&
            _ownable(p.type) &&
            '${p.address} ${p.street ?? ''}'.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  void _pick(Place p) {
    final uid = Auth.i.user?.uid;
    if (uid == null) return;
    setState(() {
      _use(ShopPage(id: shopKey(p.id), owner: uid, name: p.address, phone: p.phone ?? '', hours: p.hours ?? '', sells: [for (final v in p.accepts) v.name]));
      _place = p;
    });
  }

  ShopPage _collect() => _draft.copy(
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        hours: _hours.text.trim(),
        discountText: _dText.text.trim(),
        discountOther: _dOther.text.trim(),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = _collect();
    final ok = await ShopPages.i.save(p, p.id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _page = p;
        _draft = p;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? (p.verified ? 'Saved. Riders see it now.' : 'Saved. Riders will see the page after we check that the shop is yours.')
            : 'Could not save. Check the connection, and that nobody else has taken this shop.')));
  }

  Future<void> _addPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 900, imageQuality: 68);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 220000) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That photo is too big. Try another one.')));
        return;
      }
      setState(() => _draft = _draft.copy(photos: [..._draft.photos, base64Encode(bytes)]));
    } catch (_) {}
  }

  Future<void> _sendReward() async {
    final text = _msg.text.trim();
    if (text.length < 5) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send to every rider who checked in?'),
        content: Text('$_visits riders will get this message in the app. You can send one message a month.\n\n"$text"'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (yes != true || _page == null) return;
    final ok = await ShopPages.i.sendReward(_page!.id, _page!.name, text);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _sent = true;
        _msg.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Sent.' : 'Could not send. This month\'s message may already be gone, or the shop is not checked yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Auth.i.user != null;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('Shop owner'), backgroundColor: AppColors.paper, scrolledUnderElevation: 0),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !signedIn
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Sign in first (the account card at the top of Profile). Your shop page is tied to your account.',
                        style: TextStyle(fontSize: 15)))
                : _page == null
                    ? _pickShop()
                    : _editor(),
      ),
    );
  }

  Widget _pickShop() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Find your place', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Type its name. Shops, service hubs, rentals and BMX parks on the map are listed. Look around the map first, so your place is loaded.',
            style: TextStyle(color: AppColors.soft)),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Shop name', filled: true, fillColor: Colors.white),
        ),
        const SizedBox(height: 8),
        for (final p in _found)
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(p.street ?? p.distance),
              onTap: () => _pick(p),
            ),
          ),
        if (_search.text.trim().length >= 2 && _found.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('Not found. Move the map to your shop and try again.')),
      ]);

  String get _sellsTitle => switch (_place?.type) {
        PlaceType.service => 'What you repair',
        PlaceType.rent => 'What you rent',
        PlaceType.bmx => 'Who rides here',
        _ => 'What the shop sells',
      };

  Widget _chip(String label, bool on, ValueChanged<bool> f) =>
      FilterChip(label: Text(label), selected: on, onSelected: f, selectedColor: AppColors.slateTint, checkmarkColor: AppColors.primary);

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  InputDecoration _dec(String hint, {IconData? icon}) =>
      InputDecoration(hintText: hint, prefixIcon: icon == null ? null : Icon(icon), border: const OutlineInputBorder(), isDense: true);

  Widget _editor() {
    final d = _draft;
    final saved = _page!;
    const names = {'bike': 'Bikes', 'ebike': 'E-bikes', 'scooter': 'Scooters', 'moped': 'Mopeds', 'moto': 'Motorcycles'};
    final preview = d.copy(discountText: _dText.text, discountOther: _dOther.text).discountLine;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: saved.verified ? AppColors.greenTint : AppColors.yellowTint, borderRadius: BorderRadius.circular(14)),
        child: Text(
            saved.verified
                ? 'Live: riders see this page.'
                : 'Riders do not see this page yet. We check that the shop is yours first; you can fill everything in meanwhile.',
            style: TextStyle(fontWeight: FontWeight.w700, color: saved.verified ? AppColors.greenDark : AppColors.yellowDark)),
      ),
      const SizedBox(height: 12),
      _card('Location', [
        Row(children: [
          const Icon(Icons.storefront_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${d.name}${_place?.street == null ? '' : '\n${_place!.street}'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
      _card('Contact and hours', [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('E-mail', icon: Icons.mail_outline)),
        const SizedBox(height: 8),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('Phone', icon: Icons.phone_outlined)),
        const SizedBox(height: 8),
        TextField(controller: _hours, decoration: _dec('Hours, e.g. Mo-Fr 10:00-18:00; Sa 10:00-16:00', icon: Icons.schedule)),
      ]),
      _card(_sellsTitle, [
        Wrap(spacing: 8, children: [
          for (final e in names.entries)
            _chip(e.value, d.sells.contains(e.key), (on) {
              final l = [...d.sells];
              on ? l.add(e.key) : l.remove(e.key);
              setState(() => _draft = d.copy(sells: l));
            }),
        ]),
        const SizedBox(height: 6),
        const Text('Riders with a vehicle registered see the places that fit it.', style: TextStyle(fontSize: 12, color: AppColors.soft)),
      ]),
      _card('Photos (up to 3)', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < d.photos.length; i++)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(base64Decode(d.photos[i]), width: 96, height: 96, fit: BoxFit.cover),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: InkWell(
                  onTap: () => setState(() => _draft = d.copy(photos: [...d.photos]..removeAt(i))),
                  child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                ),
              ),
            ]),
          if (d.photos.length < 3) ...[
            OutlinedButton.icon(onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
            OutlinedButton.icon(onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Camera')),
          ],
        ]),
      ]),
      _card('Discount', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show a discount'),
          subtitle: const Text('The shop\'s page turns violet and a line under the address shows the offer.'),
          value: d.discount,
          onChanged: (v) => setState(() => _draft = d.copy(discount: v)),
        ),
        if (d.discount) ...[
          TextField(controller: _dText, onChanged: (_) => setState(() {}), decoration: _dec('How much, e.g. 15% off', icon: Icons.sell_outlined)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final k in ShopPage.discountKinds)
              _chip(k, d.discountOn.contains(k), (on) {
                final l = [...d.discountOn];
                on ? l.add(k) : l.remove(k);
                setState(() => _draft = d.copy(discountOn: l));
              }),
          ]),
          if (d.discountOn.contains('Other')) ...[
            const SizedBox(height: 8),
            TextField(controller: _dOther, onChanged: (_) => setState(() {}), decoration: _dec('Other: what is it on?')),
          ],
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFEDE3FA), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.sell_rounded, size: 16, color: Color(0xFF4A2A8A)),
                const SizedBox(width: 6),
                Expanded(child: Text(preview, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4A2A8A)))),
              ]),
            ),
          ],
        ],
      ]),
      FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(_saving ? 'Saving…' : 'Save the page'),
      ),
      const SizedBox(height: 16),
      _card('Reward your customers', [
        Text('$_visits riders have checked in with "I was here" at your shop.', style: const TextStyle(color: AppColors.soft)),
        const SizedBox(height: 8),
        if (_sent)
          const Text('This month\'s message is sent. You can send the next one next month.', style: TextStyle(fontWeight: FontWeight.w700))
        else ...[
          TextField(controller: _msg, maxLength: 200, maxLines: 3, decoration: _dec('e.g. Thanks for coming in! Show this message for a free tune-up check.')),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: !saved.verified || _visits == 0 ? null : _sendReward,
            icon: const Icon(Icons.card_giftcard),
            label: const Text('Send the reward message'),
          ),
          if (!saved.verified)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Available once the shop is checked.', style: TextStyle(fontSize: 12, color: AppColors.soft))),
        ],
      ]),
    ]);
  }
}

/// Profile → Messages from shops: what the shops rider has visited sent.
class ShopInboxScreen extends StatelessWidget {
  const ShopInboxScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(title: const Text('Messages from shops'), backgroundColor: AppColors.paper, scrolledUnderElevation: 0),
        body: FutureBuilder<List<ShopMessage>>(
          future: ShopPages.i.inbox(),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final l = snap.data ?? const [];
            if (l.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing yet. When you open a shop and tap "I was here", it can send you a message once a month.'));
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final m in l)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.card_giftcard, color: Color(0xFF7B4FD0)),
                    title: Text(m.shop, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${m.text}\n${m.at.toLocal().toString().substring(0, 10)}'),
                    isThreeLine: true,
                  ),
                ),
            ]);
          },
        ),
      );
}
