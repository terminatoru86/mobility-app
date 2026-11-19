import 'dart:async';

import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';

String arrivalTime(int minutes) {
  final t = DateTime.now().add(Duration(minutes: minutes));
  return 'arrive ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

/// Grey rounded tile used for distance and similar facts.
class FactTile extends StatelessWidget {
  final String value;
  final String label;
  const FactTile(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
          ],
        ),
      );
}

/// Accepted vehicles, one at a time. Rotates every 4 s (guests);
/// tapping fixes the vehicle. If the user saved a vehicle, it starts there
/// and does not rotate - other vehicles only by swiping.
class VehicleTile extends StatefulWidget {
  final Place place;
  final Vehicle? myVehicle;
  final ValueChanged<Vehicle>? onSelected;
  final Duration rotateEvery; // shops: what they sell turns every 2 s, like the filters
  const VehicleTile(
      {super.key, required this.place, this.myVehicle, this.onSelected, this.rotateEvery = const Duration(seconds: 4)});

  @override
  State<VehicleTile> createState() => _VehicleTileState();
}

class _VehicleTileState extends State<VehicleTile> {
  late final List<Vehicle> _list;
  late final PageController _pc;
  Timer? _timer;
  int _index = 0;
  bool _fixed = false;
  bool _mine = false;

  @override
  void initState() {
    super.initState();
    _list = widget.place.accepts.where((v) => widget.place.etaMin.containsKey(v)).toList();
    final mi = widget.myVehicle == null ? -1 : _list.indexOf(widget.myVehicle!);
    if (mi >= 0) {
      _index = mi;
      _mine = true;
    }
    _pc = PageController(initialPage: _index);
    if (!_mine && _list.length > 1) {
      _timer = Timer.periodic(widget.rotateEvery, (_) {
        if (!_fixed && mounted && _pc.hasClients) {
          _pc.animateToPage((_index + 1) % _list.length,
              duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedBorder = _fixed || _mine;
    return Container(
      height: 74,
      clipBehavior: Clip.antiAlias, // the picture never leaves the tile
      decoration: BoxDecoration(
        color: selectedBorder ? Colors.white : AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: selectedBorder ? Border.all(color: AppColors.ink, width: 1.5) : null,
      ),
      child: Stack(children: [
        PageView.builder(
          controller: _pc,
          itemCount: _list.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            final v = _list[i];
            final eta = widget.place.etaMin[v]!;
            return GestureDetector(
              onTap: () {
                setState(() => _fixed = true);
                widget.onSelected?.call(v);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 10),
                child: Row(children: [
                  // big picture, but always inside its own box (never under the minutes)
                  SizedBox(
                    width: 76,
                    height: 60,
                    child: Image.asset(v.asset, fit: BoxFit.contain, alignment: Alignment.center),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$eta min', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                        Text(arrivalTime(eta), style: const TextStyle(fontSize: 11, color: AppColors.soft)),
                      ],
                    ),
                  ),
                  if (_mine && i == _index)
                    _chip('yours')
                  else if (_fixed && i == _index)
                    _chip('fixed'),
                ]),
              ),
            );
          },
        ),
        // tiny dots, bottom-right inside the tile
        if (_list.length > 1)
          Positioned(
            right: 9,
            bottom: 7,
            child: IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  _list.length,
                  (i) => Container(
                    width: 2.5,
                    height: 2.5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index ? AppColors.ink : const Color(0x8C9AA6AB),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

/// "Busy today" bars (7:00-22:00), current hour coloured, with a History button.
class BusyChart extends StatelessWidget {
  final List<int> values;
  final Color color;
  final String title;
  final String? tag;
  final VoidCallback? onHistory;
  const BusyChart(
      {super.key, required this.values, required this.color, this.title = 'Busy today', this.tag, this.onHistory});

  @override
  Widget build(BuildContext context) {
    final now = ((DateTime.now().hour - 7) / 1.25).floor().clamp(0, values.length - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        if (tag != null)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.green, width: 1.5),
            ),
            child: Text(tag!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
          ),
        OutlinedButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.schedule, size: 14),
          label: const Text('History', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 46,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(values.length, (i) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: 46 * values[i] / 100,
                decoration: BoxDecoration(
                  color: i == now ? color : const Color(0xFFD9E1E4),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: 2),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('7', style: TextStyle(fontSize: 9, color: AppColors.soft)),
        Text('10', style: TextStyle(fontSize: 9, color: AppColors.soft)),
        Text('13', style: TextStyle(fontSize: 9, color: AppColors.soft)),
        Text('16', style: TextStyle(fontSize: 9, color: AppColors.soft)),
        Text('19', style: TextStyle(fontSize: 9, color: AppColors.soft)),
        Text('22', style: TextStyle(fontSize: 9, color: AppColors.soft)),
      ]),
    ]);
  }
}

/// Security icons with an English label below (covered and private parking).
class SecurityRow extends StatelessWidget {
  final Security s;
  const SecurityRow(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, bool?, bool)>[
      (Icons.videocam_outlined, 'Cameras', s.cameras, s.fromPhotos.contains('cameras')),
      (Icons.lightbulb_outline, 'Lighting', s.lighting, s.fromPhotos.contains('lighting')),
      (Icons.shield_outlined, 'Guard', s.guard, false),
      if (s.codeAccess) (Icons.lock_outline, 'Code', true, false) else (Icons.key_outlined, 'Limited', s.access, false),
      (Icons.nightlight_outlined, 'Overnight', s.overnight, false),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Security', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.soft)),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((e) {
          final ok = e.$3 == true;
          final unknown = e.$3 == null;
          return Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ok ? AppColors.greenTint : (unknown ? Colors.white : AppColors.greyTint),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ok ? AppColors.green : const Color(0xFFC9D1D5), width: 1.5),
                ),
                child: Icon(e.$1, size: 20, color: ok ? AppColors.greenDark : const Color(0xFFB4BEC3)),
              ),
              // "?" = not known yet; camera badge = seen in street photos
              if (unknown || e.$4)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.$4 ? AppColors.blue : AppColors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: e.$4
                        ? const Icon(Icons.photo_camera, size: 8, color: Colors.white)
                        : const Text('?', style: TextStyle(fontSize: 9, height: 1, color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(e.$2,
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w700, color: ok ? AppColors.primary : AppColors.grey)),
          ]);
        }).toList(),
      ),
      if (s.fromPhotos.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Blue mark: seen in street photos (Mapillary).',
              style: TextStyle(fontSize: 10.5, color: AppColors.soft)),
        ),
    ]);
  }
}

/// Small chips: what a place does (repairs, sales, what it rents, wash type...).
class OffersRow extends StatelessWidget {
  final List<String> offers;
  final String? title;
  const OffersRow(this.offers, {super.key, this.title});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[
          Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.soft)),
          const SizedBox(height: 6),
        ],
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in offers)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(o, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
        ]),
      ]);
}

/// A repair place: Open shop · Road service · Charging, always on ONE line. The ones it offers are filled and ticked.
class ServiceFlags extends StatelessWidget {
  final Set<String> on;
  const ServiceFlags(this.on, {super.key});
  static const labels = ['Open shop', 'Road service', 'Charging'];

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _flag(labels[i], on.contains(labels[i]))),
        ],
      ]);

  Widget _flag(String text, bool yes) => Container(
        height: 30,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: yes ? AppColors.greenTint : AppColors.paper,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: yes ? AppColors.green : AppColors.line, width: yes ? 1.5 : 1),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(yes ? Icons.check_rounded : Icons.remove_rounded, size: 14, color: yes ? AppColors.greenDark : AppColors.soft),
            const SizedBox(width: 3),
            Text(text,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: yes ? AppColors.greenDark : AppColors.soft)),
          ]),
        ),
      );
}

/// Reviews: stars, age on the right, one line of text, dots; swipe for more.
class ReviewsCarousel extends StatefulWidget {
  final Place place;
  final VoidCallback? onOpen;
  const ReviewsCarousel(this.place, {super.key, this.onOpen});
  @override
  State<ReviewsCarousel> createState() => _ReviewsCarouselState();
}

class _ReviewsCarouselState extends State<ReviewsCarousel> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final rs = widget.place.reviews;
    if (rs.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: widget.onOpen,
      child: Container(
      decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(children: [
        SizedBox(
          height: 40,
          child: PageView.builder(
            itemCount: rs.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final r = rs[i];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('★' * r.stars + '☆' * (5 - r.stars),
                      style: const TextStyle(color: Color(0xFFE0A100), fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(widget.place.rating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  Text(' (${widget.place.reviewCount})', style: const TextStyle(color: AppColors.soft, fontSize: 12)),
                  const Spacer(),
                  Text(r.when, style: const TextStyle(color: AppColors.soft, fontSize: 10.5)),
                ]),
                Text('“${r.text}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
              ]);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            rs.length,
            (i) => Container(
              width: i == _i ? 12 : 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i == _i ? AppColors.primary : const Color(0xFFC9D1D5),
              ),
            ),
          ),
        ),
      ]),
      ),
    );
  }
}

/// Q&As card: one question with its answer, "Ask a question…",
/// the chevron opens three.
class QaCard extends StatefulWidget {
  final List<QA> qa;
  final ValueChanged<String>? onAsk;
  const QaCard(this.qa, {super.key, this.onAsk});
  @override
  State<QaCard> createState() => _QaCardState();
}

class _QaCardState extends State<QaCard> {
  bool _open = false;
  final _ask = TextEditingController();

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _open ? widget.qa.take(3).toList() : widget.qa.take(1).toList();
    return Container(
      decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Row(children: [
            const Text('Q&As', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('${widget.qa.length}', style: const TextStyle(color: AppColors.soft, fontSize: 12)),
            const Spacer(),
            Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.soft),
          ]),
        ),
        for (final q in shown) ...[
          const SizedBox(height: 6),
          _row('Q', q.q, true),
          const SizedBox(height: 4),
          _row('A', q.a, false),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _ask,
          textInputAction: TextInputAction.send,
          onSubmitted: (t) {
            if (t.trim().isEmpty) return;
            widget.onAsk?.call(t.trim());
            _ask.clear();
            setState(() => _open = true);
          },
          decoration: const InputDecoration(
            hintText: 'Ask a question…',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
          ),
        ),
      ]),
    );
  }

  Widget _row(String l, String t, bool q) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: q ? AppColors.primary : AppColors.slateTint,
            borderRadius: BorderRadius.circular(6),
            border: q ? null : Border.all(color: AppColors.slate, width: 1.5),
          ),
          child: Text(l,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: q ? Colors.white : AppColors.primary)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(t,
                style: TextStyle(fontSize: 12.5, fontWeight: q ? FontWeight.w700 : FontWeight.w500))),
      ]);
}

/// Swipe-to-open button (like answering a call). Used for sharing
/// ("Open Lime"), starting a route and starting a group ride.
class SwipeButton extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onDone;
  const SwipeButton({super.key, required this.title, this.subtitle, required this.onDone});
  @override
  State<SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<SwipeButton> {
  double _x = 0;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const knob = 46.0;
      final max = c.maxWidth - knob - 8;
      return Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF34474F), AppColors.primary], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(alignment: Alignment.centerLeft, children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              if (widget.subtitle != null)
                Text(widget.subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          const Positioned(
            right: 16,
            child: Text('›››', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          Positioned(
            left: 4 + _x,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => setState(() => _x = (_x + d.delta.dx).clamp(0, max)),
              onHorizontalDragEnd: (_) {
                if (_x > max * 0.85) widget.onDone();
                setState(() => _x = 0);
              },
              child: Container(
                width: knob,
                height: knob,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right, color: AppColors.primary, size: 28),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Rent: one grey tile per vehicle, big cut-out picture, free count top-right.
class RentVehicleRow extends StatelessWidget {
  final Map<Vehicle, int> free;
  final Vehicle? selected;
  final ValueChanged<Vehicle>? onTap;
  const RentVehicleRow({super.key, required this.free, this.selected, this.onTap});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final e in free.entries)
          Expanded(
            child: GestureDetector(
              onTap: onTap == null ? null : () => onTap!(e.key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: selected == e.key ? const Color(0xFFEAF0FB) : const Color(0xFFE9EEF1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected == e.key ? AppColors.blue : Colors.transparent, width: 1.5),
                ),
                child: Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                      child: Image.asset(e.key.asset, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: e.value > 0 ? AppColors.green : AppColors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${e.value}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]);
}

/// Which of the four vehicle kinds (bike, scooter, moped, moto) a shop or service hub handles.
/// An e-bike counts as a bike. Nothing known at all: all four.
List<Vehicle> deckVehicles(Place p) {
  final a = p.accepts;
  final l = <Vehicle>[
    if (a.contains(Vehicle.bike) || a.contains(Vehicle.ebike)) Vehicle.bike,
    if (a.contains(Vehicle.scooter)) Vehicle.scooter,
    if (a.contains(Vehicle.moped)) Vehicle.moped,
    if (a.contains(Vehicle.moto)) Vehicle.moto,
  ];
  return l.isEmpty ? const [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto] : l;
}

/// The vehicles of a shop / service hub, gathered like a hand of playing cards: the bike's wheel, a bit of the
/// scooter, the moped's wheel, and the motorcycle on top. In the space that stays free: the dashboard
/// warning lights (service hub) or helmet, gloves, frame, oil (shop). A tap opens the cards: only the vehicles
/// the place really handles (2 take half the row, 1 a quarter), and the small pictograms gather in the rest.
/// A place that handles all four shows them at once and has no pictograms.
class VehicleDeck extends StatefulWidget {
  final Place place;
  const VehicleDeck(this.place, {super.key});

  @override
  State<VehicleDeck> createState() => _VehicleDeckState();
}

class _VehicleDeckState extends State<VehicleDeck> {
  bool _open = false;

  static const _kinds = [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto];
  // the lights of a dashboard (ABS, check engine, oil, water temperature, brakes, key) / what a shop also sells
  static const _service = ['abs', 'engine', 'oil', 'temp', 'brake', 'key'];
  static const _shop = ['helmet', 'oilbottle', 'gloves', 'frame'];

  static String _name(Vehicle v) => switch (v) {
        Vehicle.bike || Vehicle.ebike => 'Bikes',
        Vehicle.scooter => 'Scooters',
        Vehicle.moped => 'Mopeds',
        Vehicle.moto => 'Motos',
      };

  /// The little pictograms in the free space. Service: two rows, one over the other. Shop: mixed together,
  /// a little turned and overlapping, like things thrown on a counter.
  Widget _pictos() => LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth, h = 64.0;
        Widget img(String x, double size) => Image.asset('assets/glyphs/dash/$x.png', width: size, height: size, fit: BoxFit.contain);
        if (widget.place.type == PlaceType.service) {
          final per = (_service.length + 1) ~/ 2;
          final size = [26.0, (w - 8 - 4.0 * (per - 1)) / per, (h - 4) / 2].reduce((a, b) => a < b ? a : b);
          Widget row(List<String> l) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < l.length; i++) ...[if (i > 0) const SizedBox(width: 4), img(l[i], size)],
              ]);
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            row(_service.sublist(0, per)),
            const SizedBox(height: 4),
            row(_service.sublist(per)),
          ]));
        }
        final size = [h * 0.7, w * 0.44].reduce((a, b) => a < b ? a : b);
        const turn = [-0.16, 0.12, -0.08, 0.18];
        return Stack(children: [
          for (var i = 0; i < _shop.length; i++)
            Positioned(
              left: 4 + (w - size - 8) * i / (_shop.length - 1),
              top: i.isEven ? 1 : h - size - 1,
              child: Transform.rotate(angle: turn[i], child: img(_shop[i], size)),
            ),
        ]);
      });

  Widget _tile(Vehicle v) => Expanded(
        child: Container(
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(height: 32, child: Image.asset(v.asset, fit: BoxFit.contain)),
            const SizedBox(height: 2),
            Text(_name(v), maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ]),
        ),
      );

  Widget _paper(Widget child) => Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  /// the closed hand: four cards, each one leaving its left part (the wheel) in view
  Widget _closed() {
    const cardW = 80.0, step = 36.0;
    return Row(key: const ValueKey('closed'), children: [
      SizedBox(
        width: step * 3 + cardW + 6,
        height: 64,
        child: Stack(children: [
          for (var i = 0; i < _kinds.length; i++)
            Positioned(
              left: 3 + i * step,
              top: 0,
              child: Container(
                width: cardW,
                height: 64,
                padding: const EdgeInsets.fromLTRB(3, 6, 3, 6),
                decoration: BoxDecoration(
                  color: i == _kinds.length - 1 ? Colors.white : AppColors.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line, width: 1),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(-2, 0))],
                ),
                child: Image.asset(_kinds[i].asset, fit: BoxFit.contain, alignment: Alignment.centerLeft),
              ),
            ),
        ]),
      ),
      Expanded(child: _paper(_pictos())),
    ]);
  }

  /// the open hand: the vehicles the place handles, and the pictograms gathered in what is left
  Widget _opened(List<Vehicle> v) => Row(key: const ValueKey('open'), children: [
        for (final x in v) _tile(x),
        Expanded(flex: 4 - v.length, child: _paper(_pictos())),
      ]);

  @override
  Widget build(BuildContext context) {
    final v = deckVehicles(widget.place);
    if (v.length >= 4) return Row(children: [for (final x in _kinds) _tile(x)]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: _open ? _opened(v) : _closed()),
    );
  }
}
