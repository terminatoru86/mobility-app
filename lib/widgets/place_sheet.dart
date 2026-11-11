import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../data/app_state.dart';
import '../data/mapillary.dart';
import '../data/places.dart';
import '../data/store.dart';
import '../screens/fixit_screens.dart';
import '../screens/place_actions.dart';
import '../theme.dart';
import 'pin.dart';
import 'share_sheet.dart';
import 'sheet_parts.dart';

/// Opens the sheet of a place over the map.
/// The sheet that is open inside the app's main screen (see [showPlaceSheet] with a host).
PersistentBottomSheetController? _openSheet;

/// Closes the place sheet that sits above the main menu (a tap on the map, another tab).
void closePlaceSheet() {
  final c = _openSheet;
  _openSheet = null;
  try {
    c?.close();
  } catch (_) {}
}

Future<void> showPlaceSheet(BuildContext context, Place place,
    {Vehicle? myVehicle,
    bool showVehicleTip = false,
    VoidCallback? onTipSeen,
    VoidCallback? onTrip,
    AppState? state,
    ScaffoldState? host}) {
  // opens low, about a fifth of the screen (the status band, then your vehicle with time and
  // distance); drag up for all of it, drag down or tap the map to close
  Widget sheet(BuildContext _) => DraggableScrollableSheet(
        initialChildSize: place.share != null && !place.share!.street ? 0.34 : 0.24,
        minChildSize: 0.2,
        maxChildSize: 0.92,
        snap: true,
        snapSizes: [place.share != null && !place.share!.street ? 0.34 : 0.24, 0.92],
        expand: false,
        builder: (ctx, scroll) => PlaceSheet(
          place: place,
          scroll: scroll,
          myVehicle: myVehicle,
          showVehicleTip: showVehicleTip,
          onTipSeen: onTipSeen,
          onTrip: onTrip,
          state: state,
        ),
      );
  if (host != null) {
    // on the map: the sheet sits above the main menu (Map, Routes, Health, Community, Profile),
    // which stays in view and in use; the map behind it stays in use too
    closePlaceSheet();
    final c = host.showBottomSheet(
      sheet,
      backgroundColor: Colors.transparent,
      elevation: 0,
      enableDrag: false,
    );
    _openSheet = c;
    return c.closed.then((_) {
      if (identical(_openSheet, c)) _openSheet = null;
    });
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x14000000), // the map stays in view behind the low sheet
    builder: sheet,
  );
}

/// Opens a phone number or a web page outside the app.
Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class PlaceSheet extends StatefulWidget {
  final Place place;
  final ScrollController scroll;
  final Vehicle? myVehicle;
  final bool showVehicleTip;
  final VoidCallback? onTipSeen;
  final VoidCallback? onTrip;
  final AppState? state;
  const PlaceSheet({
    super.key,
    required this.place,
    required this.scroll,
    this.myVehicle,
    this.showVehicleTip = false,
    this.onTipSeen,
    this.onTrip,
    this.state,
  });

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  late bool _tip = widget.showVehicleTip;
  String? _opening;
  bool _copied = false;
  AppLifecycleListener? _back;

  @override
  void dispose() {
    _back?.dispose();
    super.dispose();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  // Sharing: open the operator's app; when the rider comes back, ask if the ride started.
  Future<void> _openOperator(Place p) async {
    final name = (p.operatorName ?? '').toLowerCase();
    final url = name.contains('divvy')
        ? 'https://divvybikes.com/how-it-works/get-the-app'
        : name.contains('lime')
            ? 'https://www.li.me/'
            : name.contains('bird')
                ? 'https://www.bird.co/'
                : 'https://www.google.com/search?q=${Uri.encodeComponent(p.operatorName ?? 'bike share')}';
    setState(() => _opening = 'Opening ${p.operatorName}…');
    _back?.dispose();
    _back = AppLifecycleListener(onResume: () {
      _back?.dispose();
      _back = null;
      if (mounted) _askStarted(p);
    });
    await openLink(url);
  }

  Future<void> _askStarted(Place p) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Welcome back!'),
        content: Text('You opened ${p.operatorName}. Did you start your ride?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Not yet')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    // a shared vehicle on the street takes the colour of its battery
    final c = colorsFor(p.share?.street == true ? p.share!.charge : p.shownStatus);
    const gap = SizedBox(height: 12);

    final children = <Widget>[
      if (_tip) _vehicleTip(),
      if (p.type == PlaceType.rent) ...[
        const RentVehicleRow(free: {Vehicle.bike: 6, Vehicle.scooter: 3, Vehicle.moped: 2, Vehicle.moto: 1}),
        const SizedBox(height: 8),
      ],
      if (p.share != null)
        // live ride share: a station shows its four numbers and the walk; one vehicle shows its
        // picture with the battery, and the walking time where the distance is
        p.share!.street ? ShareVehicleRow(p) : ShareCounts(p)
      else
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: VehicleTile(
            place: p,
            myVehicle: widget.myVehicle,
            // shops and service: only what they sell / fix, turning every 2 s when there is more than one
            rotateEvery: (p.type == PlaceType.shop || p.type == PlaceType.service)
                ? const Duration(seconds: 2)
                : const Duration(seconds: 4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: FactTile(p.distance, 'distance')),
      ]),
      gap,
      ..._specific(p, c),
      if (p.hours != null || p.phone != null || p.website != null) ...[gap, _hoursRow(p)],
      if (p.type.group == 'Parking') _securitySection(p),
      if (p.reviews.isNotEmpty)
        ...[gap, ReviewsCarousel(p, onOpen: () => _push(ReviewsScreen(place: p, state: widget.state)))]
      else if (!p.type.isNeutral || p.osm)
        ...[gap, Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _push(ReviewsScreen(place: p, state: widget.state)),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Write the first review'),
          ),
        )],
      if (p.photos.isNotEmpty)
        ...[gap, _realPhotos(p.photos)]
      else if (p.osm)
        // no photo in the map data: the nearest street photos from Mapillary (if any)
        FutureBuilder<List<String>>(
          future: mapillaryPhotos(p.pos),
          builder: (_, snap) => (snap.data ?? const []).isEmpty
              ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(top: 12), child: _realPhotos(snap.data!, credit: 'Mapillary')),
        )
      else
        ...[gap, _photo()],
      if (p.qa.isNotEmpty || (Store.i.myQuestions[p.id]?.isNotEmpty ?? false))
        if (p.type == PlaceType.parkPrivate || p.type == PlaceType.service || p.type == PlaceType.rent)
          ...[gap, QaCard([...?Store.i.myQuestions[p.id], ...p.qa], onAsk: (q) => setState(() => Store.i.ask(p.id, q)))],
      if (p.osm) ...[
        gap,
        const Text('Place data © OpenStreetMap contributors. Status, spots and ratings are test data for now.',
            style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ],
      const SizedBox(height: 24),
    ];

    // The whole sheet in the colour of its pin (a light tone of it), a little see-through and
    // frosted: pins behind it show as a blur of colour, never through it. One line in the status
    // colour all around, round corners at the bottom too, where it meets the main menu.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(c.tint, Colors.white, 0.5)!.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.main, width: 2),
            ),
            child: ListView(
              controller: widget.scroll,
              padding: EdgeInsets.zero,
              children: [
                _band(p, c),
                Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 0), child: Column(children: children)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Coloured band: glyph (or operator name), age, address + copy, Trip.
  Widget _band(Place p, StatusColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Column(children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: c.main.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (p.operatorName != null)
                  Text(p.operatorName!, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c.dark))
                else
                  Glyph(p.type, size: 24, color: c.dark),
                const SizedBox(width: 8),
                if (!p.type.isNeutral && p.age.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.main, width: 1.5),
                    ),
                    child: Text(p.age, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.dark)),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(
                  child: Text(p.address,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.dark)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, color: c.dark),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.address));
                    setState(() => _copied = true);
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(Store.i.isSaved(p) ? Icons.favorite : Icons.favorite_border,
                      color: Store.i.isSaved(p) ? AppColors.red : c.dark),
                  onPressed: () => setState(() => Store.i.toggleSaved(p)),
                ),
              ]),
            ]),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onTrip?.call();
            },
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text('Trip'),
            style: FilledButton.styleFrom(
              backgroundColor: c.dark,
              minimumSize: const Size(96, 44),
            ),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _specific(Place p, StatusColors c) {
    switch (p.type) {
      case PlaceType.parkPrivate:
        return [
          // who may use it (on private property: residents, staff, customers)
          if (p.offers.isNotEmpty) ...[OffersRow(p.offers), const SizedBox(height: 12)],
          if (p.busy.isNotEmpty)
            p.priceNow == null
                ? BusyChart(values: p.busy, color: c.main, onHistory: () => _push(HistoryScreen(place: p)))
                : BusyChart(
                    values: p.busy,
                    color: AppColors.red,
                    title: 'Price today · now ${p.priceNow}',
                    onHistory: () => _push(HistoryScreen(place: p, price: true)),
                  ),
        ];
      case PlaceType.parkOutdoor:
      case PlaceType.parkCovered:
        if (p.busy.isEmpty) return [];
        return [BusyChart(values: p.busy, color: c.main, onHistory: () => _push(HistoryScreen(place: p)))];
      case PlaceType.wash:
        return [
          // who washes: a machine, the staff, or the rider
          if (p.offers.isNotEmpty) OffersRow(p.offers),
          if (p.offers.isNotEmpty && p.busy.isNotEmpty) const SizedBox(height: 12),
          if (p.busy.isNotEmpty)
            BusyChart(values: p.busy, color: c.main, tag: p.tag, onHistory: () => _push(HistoryScreen(place: p))),
        ];
      case PlaceType.charging:
        if (p.busy.isEmpty) return [];
        return [
          BusyChart(values: p.busy, color: c.main, tag: p.tag, onHistory: () => _push(HistoryScreen(place: p))),
        ];
      case PlaceType.selfService:
        return [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in p.tools) _chip(t, AppColors.paper, AppColors.primary, AppColors.slate),
            _chip('★ Free', AppColors.greenTint, AppColors.greenDark, AppColors.green),
          ]),
          const SizedBox(height: 12),
          // scan the QR on the stand: the maker's instructions open inside the app
          FilledButton.icon(
            onPressed: () => _push(FixitScanScreen(brand: p.operatorName)),
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Fixit help · scan the QR'),
          ),
        ];
      case PlaceType.service:
        return [
          if (p.osm)
            // real place: only what the map data says it does
            if (p.offers.isNotEmpty) OffersRow(p.offers, title: 'What they do') else const SizedBox.shrink()
          else
            Wrap(spacing: 6, children: [
              _chip('Open Service', AppColors.paper, AppColors.primary, AppColors.slate),
              _chip('Road Service', AppColors.paper, AppColors.primary, AppColors.slate),
              _chip('Charging', AppColors.yellowTint, AppColors.yellowDark, AppColors.yellow),
            ]),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _push(ServiceRequestScreen(place: p, state: widget.state)),
            child: const Text('Book a service'),
          ),
        ];
      case PlaceType.rent:
        return [
          if (p.offers.isNotEmpty) ...[OffersRow(p.offers, title: 'For rent'), const SizedBox(height: 12)],
          FilledButton(onPressed: () => _push(RentScreen(place: p)), child: const Text('Reserve / Rent')),
        ];
      case PlaceType.shop:
      case PlaceType.bmx:
        return p.offers.isEmpty ? [] : [OffersRow(p.offers, title: p.type == PlaceType.shop ? 'What they offer' : 'Track')];
      case PlaceType.sharing:
        return [
          SwipeButton(
            title: _opening ?? 'Open ${p.operatorName}',
            subtitle: p.operatorPrice,
            onDone: () => _openOperator(p),
          ),
        ];
      default:
        return [];
    }
  }

  Widget _hoursRow(Place p) {
    final web = p.website == null ? null : Uri.tryParse(p.website!.startsWith('http') ? p.website! : 'https://${p.website}');
    final pill = OutlinedButton.styleFrom(
      foregroundColor: AppColors.ink,
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (p.hours != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_open_rounded, size: 18, color: AppColors.green),
          const SizedBox(width: 6),
          Text(p.hours!, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.greenDark)),
        ]),
      if (p.phone != null)
        OutlinedButton.icon(
          onPressed: () => openLink('tel:${p.phone!.replaceAll(RegExp(r'[^0-9+]'), '')}'),
          icon: const Icon(Icons.phone_outlined, size: 16),
          label: Text(p.phone!),
          style: pill,
        ),
      if (web != null && web.host.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => openLink(web.toString()),
          icon: const Icon(Icons.language, size: 16),
          label: Text(web.host.replaceFirst('www.', '')),
          style: pill,
        ),
    ]);
  }

  /// Parking security: map data, plus cameras and street lights seen in Mapillary street photos.
  Widget _securitySection(Place p) {
    final base = p.security ?? const Security(cameras: null, lighting: null, guard: null, access: null, overnight: null);
    return FutureBuilder<Set<String>>(
      future: p.osm ? mapillarySecurity(p.pos) : Future.value(const <String>{}),
      builder: (_, snap) {
        final s = base.withPhotos(snap.data ?? const {});
        if (!s.anyKnown) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(top: 12), child: SecurityRow(s));
      },
    );
  }

  /// Real photos of the place (from OpenStreetMap / Wikimedia Commons / Panoramax), swipe through them.
  Widget _realPhotos(List<String> urls, {String? credit}) => SizedBox(
        height: 170,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: PageView.builder(
            itemCount: urls.length,
            itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
              Image.network(
                urls[i],
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) =>
                    prog == null ? child : Container(color: AppColors.paper, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.paper,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined, color: AppColors.soft),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text('Photo · ${i + 1}/${urls.length}${credit == null ? '' : ' · $credit'}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _photo() => Container(
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD5E3EA), Color(0xFFD5E3EA), Color(0xFFA1B2A0), Color(0xFFA1B2A0)],
            stops: [0, 0.55, 0.55, 1],
          ),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
          child: const Text('Photo · 1/3', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _chip(String t, Color bg, Color fg, Color border) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
      );

  // Step 8 of the guide: shown the first time a sheet is opened.
  Widget _vehicleTip() => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.green, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('8 OF 8', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.greenDark)),
          const SizedBox(height: 2),
          const Text('Accepted vehicles', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          const Text(
            'Only the vehicles accepted here appear below, one every 4 seconds, each with its time and arrival. '
            'If yours is missing, this place has no room for it. With an account the sheet starts from your vehicle; swipe to see the others.',
            style: TextStyle(fontSize: 12.5, color: AppColors.soft),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _tip = false);
                widget.onTipSeen?.call();
              },
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      );
}
