import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/places.dart';
import '../theme.dart';
import 'pin.dart';
import 'sheet_parts.dart';

/// Opens the sheet of a place over the map.
Future<void> showPlaceSheet(BuildContext context, Place place,
    {Vehicle? myVehicle, bool showVehicleTip = false, VoidCallback? onTipSeen}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scroll) => PlaceSheet(
        place: place,
        scroll: scroll,
        myVehicle: myVehicle,
        showVehicleTip: showVehicleTip,
        onTipSeen: onTipSeen,
      ),
    ),
  );
}

class PlaceSheet extends StatefulWidget {
  final Place place;
  final ScrollController scroll;
  final Vehicle? myVehicle;
  final bool showVehicleTip;
  final VoidCallback? onTipSeen;
  const PlaceSheet({
    super.key,
    required this.place,
    required this.scroll,
    this.myVehicle,
    this.showVehicleTip = false,
    this.onTipSeen,
  });

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  late bool _tip = widget.showVehicleTip;
  String? _opening;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final c = colorsFor(p.shownStatus);
    const gap = SizedBox(height: 12);

    final children = <Widget>[
      if (_tip) _vehicleTip(),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: VehicleTile(place: p, myVehicle: widget.myVehicle)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: FactTile(p.distance, 'distance')),
      ]),
      gap,
      ...(p.osm ? _osmFacts(p) : _specific(p, c)),
      if (p.hours != null || p.phone != null) ...[gap, _hoursRow(p)],
      if (p.security != null) ...[gap, SecurityRow(p.security!)],
      if (p.reviews.isNotEmpty) ...[gap, ReviewsCarousel(p)],
      if (!p.osm) ...[gap, _photo()],
      if (p.qa.isNotEmpty) ...[gap, QaCard(p.qa)],
      if (p.osm) ...[
        gap,
        const Text('Place data © OpenStreetMap contributors. Live status comes from riders’ reports.',
            style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ],
      const SizedBox(height: 24),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: ListView(
        controller: widget.scroll,
        padding: EdgeInsets.zero,
        children: [
          _band(p, c),
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Column(children: children)),
        ],
      ),
    );
  }

  // Coloured band: glyph (or operator name), age, address + copy, Trip.
  Widget _band(Place p, StatusColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.tint,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: c.main, width: 2), left: BorderSide(color: c.main, width: 2), right: BorderSide(color: c.main, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
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
                  icon: Icon(Icons.copy_rounded, color: c.dark),
                  onPressed: () => Clipboard.setData(ClipboardData(text: p.address)),
                ),
              ]),
            ]),
          ),
          FilledButton.icon(
            onPressed: () {},
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
        return [BusyChart(values: p.busy, color: AppColors.red, title: 'Price today · now ${p.priceNow}')];
      case PlaceType.parkOutdoor:
      case PlaceType.parkCovered:
        return [BusyChart(values: p.busy, color: c.main)];
      case PlaceType.wash:
      case PlaceType.charging:
        return [BusyChart(values: p.busy, color: c.main, tag: p.tag)];
      case PlaceType.selfService:
        return [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in p.tools) _chip(t, AppColors.paper, AppColors.primary, AppColors.slate),
            _chip('★ Free', AppColors.greenTint, AppColors.greenDark, AppColors.green),
          ])
        ];
      case PlaceType.service:
        return [
          Wrap(spacing: 6, children: [
            _chip('Open Service', AppColors.paper, AppColors.primary, AppColors.slate),
            _chip('Road Service', AppColors.paper, AppColors.primary, AppColors.slate),
            _chip('Charging', AppColors.yellowTint, AppColors.yellowDark, AppColors.yellow),
          ]),
          const SizedBox(height: 12),
          FilledButton(onPressed: () {}, child: const Text('Book a service')),
        ];
      case PlaceType.rent:
        return [FilledButton(onPressed: () {}, child: const Text('Reserve / Rent'))];
      case PlaceType.sharing:
        return [
          SwipeButton(
            title: _opening ?? 'Open ${p.operatorName}',
            subtitle: p.operatorPrice,
            onDone: () => setState(() => _opening = 'Opening ${p.operatorName}…'),
          ),
        ];
      default:
        return [];
    }
  }

  // Real places from OpenStreetMap: what the map knows about the place.
  List<Widget> _osmFacts(Place p) {
    final chips = [
      for (final f in p.facts)
        f == 'Free'
            ? _chip('★ Free', AppColors.greenTint, AppColors.greenDark, AppColors.green)
            : _chip(f, AppColors.paper, AppColors.primary, AppColors.slate),
    ];
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(p.type.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
      ],
      if (p.website != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(p.website!, style: const TextStyle(fontSize: 12, color: AppColors.blue)),
        ),
      ],
    ];
  }

  Widget _hoursRow(Place p) => Row(children: [
        if (p.hours != null) ...[
          const Icon(Icons.lock_open_rounded, size: 18, color: AppColors.green),
          const SizedBox(width: 6),
          Text(p.hours!, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.greenDark)),
        ],
        const Spacer(),
        if (p.phone != null)
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.phone_outlined, size: 16),
            label: Text(p.phone!),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, shape: const StadiumBorder()),
          ),
      ]);

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
            'Only the vehicles accepted here appear below, one every 20 seconds, each with its time and arrival. '
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
