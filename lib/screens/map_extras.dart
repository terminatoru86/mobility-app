import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/store.dart';
import '../data/weather.dart';
import '../theme.dart';
import '../widgets/pin.dart';

// ───────────────────────── 3.2 Weather ─────────────────────────

Future<void> showWeather(BuildContext context, Weather w) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _WeatherSheet(w),
    );

class _WeatherSheet extends StatefulWidget {
  final Weather w;
  const _WeatherSheet(this.w);
  @override
  State<_WeatherSheet> createState() => _WeatherSheetState();
}

class _WeatherSheetState extends State<_WeatherSheet> {
  String _tab = 'Rain';

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final rainIn = w.rainInMinutes;
    final chance = w.rainChance.isEmpty ? 0 : w.rainChance.reduce((a, b) => a > b ? a : b);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Clouds', label: Text('Clouds')),
              ButtonSegment(value: 'Rain', label: Text('Rain')),
              ButtonSegment(value: 'Wind', label: Text('Wind')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 14),
          if (_tab == 'Clouds') ...[
            Text('${w.temp.round()}° · ${w.sky}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(rainIn == null ? 'No rain in the next 2 hours.' : 'Rain expected in about $rainIn min.',
                style: const TextStyle(color: AppColors.soft)),
          ],
          if (_tab == 'Rain') ...[
            Text(rainIn == null ? '☀ No rain in the next 2 hours' : '☂ Rain in $rainIn min',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.blue)),
            Text('$chance% chance in the next hours · ${w.temp.round()}°', style: const TextStyle(color: AppColors.soft)),
            const SizedBox(height: 14),
            SizedBox(
              height: 70,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (int k = 0; k < w.rain.length; k++)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        height: 6 + (w.rain[k] * 40).clamp(0, 44).toDouble(),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: w.rain[k] >= 1
                              ? AppColors.red
                              : (w.rain[k] >= 0.3 ? AppColors.yellow : const Color(0xFFBBD0F5)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(k == 0 ? 'Now' : '+${k * 15}',
                          style: const TextStyle(fontSize: 10, color: AppColors.soft, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('🔵 Light   🟡 Moderate   🔴 Heavy', style: TextStyle(fontSize: 12)),
          ],
          if (_tab == 'Wind') ...[
            Text('💨 Wind ${w.wind.round()} km/h from ${w.windFrom}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text('Gusts up to ${w.gusts.round()} km/h', style: const TextStyle(color: AppColors.soft)),
            const SizedBox(height: 10),
            Row(children: [
              Transform.rotate(
                angle: (w.windDir + 180) * 3.14159 / 180,
                child: const Icon(Icons.navigation_rounded, size: 40, color: AppColors.blue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Riding towards ${_opposite(w.windFrom)} you have it at your back; towards ${w.windFrom}, in your face.',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              w.wind < 15 ? '● Light' : (w.wind < 30 ? '● Moderate' : '● Strong'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: w.wind < 15 ? AppColors.green : (w.wind < 30 ? AppColors.yellowDark : AppColors.red),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text('Weather © Open-Meteo', style: TextStyle(fontSize: 10, color: AppColors.soft)),
        ]),
      ),
    );
  }

  String _opposite(String d) => const {
        'N': 'S',
        'NE': 'SW',
        'E': 'W',
        'SE': 'NW',
        'S': 'N',
        'SW': 'NE',
        'W': 'E',
        'NW': 'SE',
      }[d] ??
      d;
}

// ───────────────────────── 3.6 SOS ─────────────────────────

/// Opened after holding SOS for 3 seconds: the camera first (photo optional),
/// with one note line over it: X outside on the left, the send arrow in a red bubble.
Future<void> showSosComposer(BuildContext context) => Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _SosCamera(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));

class _SosCamera extends StatefulWidget {
  const _SosCamera();
  @override
  State<_SosCamera> createState() => _SosCameraState();
}

class _SosCameraState extends State<_SosCamera> {
  final _t = TextEditingController();
  Uint8List? _photo;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 80);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (mounted) setState(() => _photo = b);
    } catch (_) {}
  }

  void _send() {
    Store.i.startSos(_t.text.trim().isEmpty ? 'Need help' : _t.text.trim(), photo: _photo, at: userPos);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final first = !Store.i.sosFirstUseShown;
    final pad = MediaQuery.of(context).padding;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1215),
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        // viewfinder / the photo just taken
        Positioned.fill(
          child: _photo != null
              ? Image.memory(_photo!, fit: BoxFit.cover)
              : const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [Color(0xFF2A3238), Color(0xFF0E1215)], radius: 0.9),
                  ),
                ),
        ),
        // SOS tag, top-left
        Positioned(
          left: 14,
          top: pad.top + 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(14)),
            child: const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),
        ),
        if (_photo == null)
          Positioned(
            left: 0,
            right: 0,
            top: pad.top + 60,
            child: const Text('Take a photo (optional)',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          ),
        if (first)
          Positioned(
            left: 16,
            right: 16,
            top: pad.top + 90,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text('Riders within 2 miles with the app open will see your alert. In danger? Call 911.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
        // the note line, then the shutter
        Positioned(
          left: 12,
          right: 12,
          bottom: (kb > 0 ? kb + 10 : pad.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23)),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _t,
                        maxLength: 300,
                        maxLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'What happened?',
                          counterText: '',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
            if (kb == 0) ...[
              const SizedBox(height: 22),
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _photo == null ? Colors.white : AppColors.green,
                    ),
                    child: _photo == null ? null : const Icon(Icons.refresh, color: Colors.white),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── SOS received: a note at the bottom, with the photo only behind the note ──

class SosNote extends StatelessWidget {
  final IncomingSos sos;
  final VoidCallback onHelp;
  const SosNote({super.key, required this.sos, required this.onHelp});

  Widget _photo(IncomingSos s) => s.photo != null
      ? Image.memory(s.photo!, fit: BoxFit.cover)
      : Container(
          color: const Color(0xFF3A4249),
          alignment: Alignment.center,
          child: s.photoAsset == null ? null : Image.asset(s.photoAsset!, fit: BoxFit.contain),
        );

  @override
  Widget build(BuildContext context) {
    final km = const Distance()(userPos, sos.pos) / 1000;
    final ago = DateTime.now().difference(sos.at).inMinutes;
    final hasPhoto = sos.photo != null || sos.photoAsset != null;
    return Dismissible(
      key: ValueKey(sos.at),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => Store.i.dismissIncomingSos(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: hasPhoto ? () => _enlarge(context) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(children: [
              if (hasPhoto)
                Positioned.fill(
                  child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3), child: _photo(sos)),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: hasPhoto ? Colors.black.withValues(alpha: 0.45) : const Color(0xFFFFF4C9),
                  border: Border(left: BorderSide(color: AppColors.red, width: 4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('“${sos.text}”',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15, color: hasPhoto ? Colors.white : AppColors.ink)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                        '${km.toStringAsFixed(1)} km · ${ago <= 0 ? 'now' : '$ago min ago'} · approximate area',
                        style: TextStyle(fontSize: 11.5, color: hasPhoto ? Colors.white70 : AppColors.soft),
                      ),
                    ),
                    Text('›››', style: TextStyle(color: hasPhoto ? Colors.white54 : AppColors.soft, letterSpacing: 1)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: onHelp,
              style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(0, 44), shape: const StadiumBorder()),
              child: const Text('I can help', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: Store.i.dismissIncomingSos,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: const StadiumBorder(),
              ),
              child: const Text("Can't", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
          ),
        ]),
      ]),
    );
  }

  // the photo, bigger, in a card in the middle (not full screen); tap again to close
  void _enlarge(BuildContext context) => showDialog<void>(
        context: context,
        barrierColor: Colors.black38,
        builder: (c) => GestureDetector(
          onTap: () => Navigator.pop(c),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 24)],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AspectRatio(aspectRatio: 4 / 3, child: _photo(sos)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('“${sos.text}”',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink, decoration: TextDecoration.none)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// On my phone after my SOS: someone is coming.
class SosHelperCard extends StatelessWidget {
  final SosHelper helper;
  const SosHelperCard({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    final min = math.max(1, (helper.meters / 1000 / 18 * 60).round());
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.green,
          child: Text(helper.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${helper.name} is coming to you', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            Text('$min min · ${(helper.meters / 1000).toStringAsFixed(1)} km · alert removed for the others',
                style: const TextStyle(fontSize: 11.5, color: AppColors.soft)),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── 3.7 Report ─────────────────────────

const _kinds = [
  ('New place', Icons.add_location_alt_outlined, AppColors.green),
  ('Abandoned vehicle', Icons.no_transfer, AppColors.slate),
  ('Blocked road', Icons.block, AppColors.red),
  ('Risk zone', Icons.warning_amber_rounded, AppColors.yellow),
  ('Map correction', Icons.signpost_outlined, AppColors.blue),
  ('Suggestion', Icons.lightbulb_outline, AppColors.primary),
  ('I like this lane', Icons.favorite, AppColors.red),
];

const _choices = {
  'New place': ['Rack', 'Parking', 'Pump', 'Wash', 'Charging', 'Self-service', 'Service', 'Shop'],
  'Blocked road': ['Construction', 'Festival', 'Parade', 'Accident', 'Road closed'],
  'Risk zone': ['🕳️ Potholes', '🪨 Rough gravel', '🌊 Flooding', '🐕 Dogs'],
  'Map correction': [
    '🛑 Stop', '🚦 Light', '⛔ No entry', '⚠️ Caution', '🚸 Pedestrians', '🔻 Yield', //
    '🚲 Bike lane', '🅿️ Parking', '🚧 Works', '🚳 No bikes', '➡️ One way', '➕ Other',
  ],
};

class ReportMenu extends StatelessWidget {
  final LatLng pos;
  const ReportMenu({super.key, required this.pos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Report')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Choose what to report', style: TextStyle(color: AppColors.soft)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            for (final (name, icon, color) in _kinds)
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) =>
                        name == 'Abandoned vehicle' ? AbandonedCamera(pos: pos) : ReportForm(kind: name, pos: pos),
                  )),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('Location and time are added automatically.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.soft)),
      ]),
    );
  }
}

class ReportForm extends StatefulWidget {
  final String kind;
  final LatLng pos;
  const ReportForm({super.key, required this.kind, required this.pos});
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  String? _pick;
  bool _photo = false;
  final _text = TextEditingController();

  bool get _photoNeeded => widget.kind != 'Suggestion';
  bool get _ok => (!_photoNeeded || _photo) && (_choices[widget.kind] == null || _pick != null);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices[widget.kind];
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: Text(widget.kind)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (choices != null) ...[
          Text(
            switch (widget.kind) {
              'New place' => 'Type of place',
              'Blocked road' => 'What is happening',
              'Risk zone' => 'What you saw',
              _ => 'Choose the sign on the map',
            },
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in choices)
              ChoiceChip(label: Text(c), selected: _pick == c, onSelected: (_) => setState(() => _pick = c)),
          ]),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.my_location, color: AppColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'My location · ${widget.pos.latitude.toStringAsFixed(4)}, ${widget.pos.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Text('move the pin', style: TextStyle(color: AppColors.soft, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _photo = !_photo),
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: _photo ? AppColors.greenTint : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _photo ? AppColors.green : AppColors.line, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(_photo ? '✓ Photo added' : '📷 Take a photo or choose from gallery${_photoNeeded ? '' : ' (optional)'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          maxLength: 3000,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Describe it: what, where, until when…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _ok
              ? () {
                  Store.i.addReport(Report(widget.kind, _pick ?? '', _text.text.trim(), widget.pos, DateTime.now()));
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Send report'),
        ),
        if (!_ok && _photoNeeded && !_photo)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('The report needs a photo', textAlign: TextAlign.center, style: TextStyle(color: AppColors.soft)),
          ),
      ]),
    );
  }
}

/// Abandoned vehicle: the camera opens directly; closing it sends the report.
class AbandonedCamera extends StatelessWidget {
  final LatLng pos;
  const AbandonedCamera({super.key, required this.pos});

  @override
  Widget build(BuildContext context) {
    void send() {
      Store.i.addReport(Report('Abandoned vehicle', '', '', pos, DateTime.now()));
      Navigator.pop(context);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141A1C),
      body: SafeArea(
        child: Stack(children: [
          Positioned(left: 8, top: 8, child: IconButton(onPressed: send, icon: const Icon(Icons.close, color: Colors.white))),
          const Positioned(
            left: 20,
            right: 20,
            top: 60,
            child: Column(children: [
              Text('Photograph the vehicle and the lock',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              SizedBox(height: 4),
              Text('📍 Location and time are added automatically · closing sends it',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Center(
            child: Container(
              width: 260,
              height: 200,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: GestureDetector(
                onTap: send,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  padding: const EdgeInsets.all(5),
                  child: const DecoratedBox(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── 3.1 List view ─────────────────────────

class PlacesList extends StatefulWidget {
  final List<Place> places; // already sorted by distance
  final ValueChanged<Place> onOpen;
  const PlacesList({super.key, required this.places, required this.onOpen});
  @override
  State<PlacesList> createState() => _PlacesListState();
}

class _PlacesListState extends State<PlacesList> {
  String _f = 'All';

  @override
  Widget build(BuildContext context) {
    var list = widget.places;
    if (_f == 'Only green') list = list.where((p) => p.shownStatus == Status.free).toList();
    if (_f == 'Covered') list = list.where((p) => p.type == PlaceType.parkCovered).toList();
    if (_f == 'Open now') list = list.where((p) => p.hours == null || p.hours!.contains('24')).toList();
    int n(Status s) => widget.places.where((p) => p.shownStatus == s).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(children: [
          _count(n(Status.free), AppColors.green),
          _count(n(Status.almost), AppColors.yellow),
          _count(n(Status.full), AppColors.red),
          const Spacer(),
          Text('${widget.places.length} nearby', style: const TextStyle(color: AppColors.soft)),
        ]),
      ),
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final f in const ['All', 'Only green', 'Open now', 'Covered'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(f), selected: _f == f, onSelected: (_) => setState(() => _f = f)),
            ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final p = list[i];
            final c = colorsFor(p.shownStatus);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onOpen(p),
                  child: Row(children: [
                    Container(width: 6, height: 62, color: c.main),
                    const SizedBox(width: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: Glyph(p.type, size: 20, color: c.dark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.address,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          p.type.isNeutral
                              ? '${p.type.title}${p.reviewCount > 0 ? ' · ${p.rating.toStringAsFixed(1)} ★' : ''}'
                              : '${p.count ?? '—'}${_cap(p)} · ${p.age.isEmpty ? 'no data' : p.age}',
                          style: TextStyle(color: c.dark, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(p.distance, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${p.etaMin.values.isEmpty ? '-' : p.etaMin.values.first} min',
                            style: const TextStyle(fontSize: 11, color: AppColors.soft)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  String _cap(Place p) {
    final f = p.facts.where((x) => x.startsWith('Capacity ')).toList();
    return f.isEmpty ? '' : ' / ${f.first.substring(9)}';
  }

  Widget _count(int n, Color c) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(children: [
          Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c)),
          const SizedBox(width: 3),
          Icon(Icons.circle, size: 9, color: c),
        ]),
      );
}
