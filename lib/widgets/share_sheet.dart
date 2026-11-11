import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/places.dart';
import '../data/routing.dart';
import '../theme.dart';
import 'place_sheet.dart' show openLink;
import 'share_pin.dart';

/// Walking: about 80 metres a minute, paths are longer than the straight line.
int walkMinutes(double meters) => (meters / 80).ceil().clamp(1, 999);

double metersTo(Place p) => const Distance()(userPos, p.pos) * 1.25;

/// Where the operator's own app (or page) opens: the ride is unlocked and paid there.
String operatorUrl(Place p) {
  final name = (p.operatorName ?? '').toLowerCase();
  return name.contains('divvy')
      ? 'https://divvybikes.com/how-it-works/get-the-app'
      : name.contains('lime')
          ? 'https://www.li.me/'
          : name.contains('bird')
              ? 'https://www.bird.co/'
              : name.contains('spin')
                  ? 'https://www.spin.app/'
                  : 'https://www.google.com/search?q=${Uri.encodeComponent(p.operatorName ?? 'bike share')}';
}

/// The low sheet of a ride-share pin: the map stays in view.
///  · a station: what is available now, each kind with its number, and the open docks
///  · a vehicle on the street: what it is, battery, range
/// One button: walk there.
Future<void> showShareSheet(BuildContext context, Place p, {required VoidCallback onWalk}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x14000000),
      builder: (c) => ShareSheetCard(place: p, onWalk: onWalk),
    );

class ShareSheetCard extends StatelessWidget {
  final Place place;
  final VoidCallback onWalk;
  const ShareSheetCard({required this.place, required this.onWalk});

  @override
  Widget build(BuildContext context) {
    final p = place, s = p.share!;
    final m = metersTo(p);
    final op = p.operatorName ?? 'Ride share';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x260F1E24), blurRadius: 24, offset: Offset(0, -8))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              if (s.street) ...[
                Image.asset(s.vehicle.asset, width: 46, height: 40, fit: BoxFit.contain),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(
                      [
                        if (!s.street) op,
                        if (s.street && s.code != null) 'No. ${s.code}',
                        '${fmtDistance(m)} · ${walkMinutes(m)} min walk',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.soft)),
                ]),
              ),
              GestureDetector(
                onTap: () => openLink(operatorUrl(p)),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                  child: Text('$op ›',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.blue)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (s.street) _battery(s) else _counts(s),
            if (p.operatorPrice != null) ...[
              const SizedBox(height: 8),
              Text(p.operatorPrice!, style: const TextStyle(fontSize: 12.5, color: AppColors.soft)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onWalk();
              },
              icon: const Icon(Icons.directions_walk_rounded, size: 20),
              label: Text('Walk there · ${walkMinutes(m)} min'),
            ),
          ]),
        ),
      ),
    );
  }

  /// A station: one tile for each kind, the number big; nothing available shows in grey.
  Widget _counts(ShareInfo s) {
    Widget tile(IconData icon, int n, String label, {bool dock = false}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: n == 0 ? AppColors.greyTint : (dock ? AppColors.slateTint : AppColors.greenTint),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: n == 0 ? AppColors.grey : (dock ? AppColors.primary : AppColors.greenDark)),
                const SizedBox(width: 4),
                Text('$n',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900, color: n == 0 ? AppColors.greyDark : AppColors.ink)),
              ]),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
            ]),
          ),
        );
    return Row(children: [
      tile(Icons.electric_bike_rounded, s.ebikes, 'E-bikes'),
      tile(Icons.pedal_bike_rounded, s.classic, 'Classic'),
      if (s.scooters > 0) tile(Icons.electric_scooter_rounded, s.scooters, 'Scooters'),
      if (s.docks != null) tile(Icons.local_parking_rounded, s.docks!, 'Open docks', dock: true),
    ]);
  }

  /// A street vehicle: the battery as a bar in its colour, and how far it still goes.
  Widget _battery(ShareInfo s) {
    final pct = s.battery;
    final c = chargeColor(pct);
    final miles = s.rangeM == null ? null : s.rangeM! / 1609.34;
    return Row(children: [
      Icon(Icons.bolt_rounded, size: 20, color: c),
      const SizedBox(width: 4),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pct == null ? null : pct / 100,
            minHeight: 9,
            color: c,
            backgroundColor: AppColors.greyTint,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text(
          [
            if (pct != null) '$pct%',
            if (miles != null) '${miles < 10 ? miles.toStringAsFixed(1) : miles.round()} mi',
          ].join(' · '),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
    ]);
  }
}
