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
  const VehicleTile({super.key, required this.place, this.myVehicle, this.onSelected});

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
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
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
                padding: const EdgeInsets.only(left: 6, right: 10),
                child: Row(children: [
                  // bigger picture: the cut-out image overflows its box a little
                  SizedBox(
                    width: 74,
                    height: 62,
                    child: Transform.scale(scale: 1.3, child: Image.asset(v.asset, fit: BoxFit.contain)),
                  ),
                  const SizedBox(width: 8),
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
    final items = <(IconData, String, bool)>[
      (Icons.videocam_outlined, 'Cameras', s.cameras),
      (Icons.lightbulb_outline, 'Lighting', s.lighting),
      (Icons.shield_outlined, 'Guard', s.guard),
      if (s.codeAccess) (Icons.lock_outline, 'Code', true) else (Icons.key_outlined, 'Access', s.access),
      (Icons.nightlight_outlined, 'Overnight', s.overnight),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Security', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.soft)),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((e) {
          final ok = e.$3;
          return Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ok ? AppColors.greenTint : AppColors.greyTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ok ? AppColors.green : const Color(0xFFC9D1D5), width: 1.5),
              ),
              child: Icon(e.$1, size: 20, color: ok ? AppColors.greenDark : AppColors.grey),
            ),
            const SizedBox(height: 3),
            Text(e.$2,
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w700, color: ok ? AppColors.primary : AppColors.grey)),
          ]);
        }).toList(),
      ),
    ]);
  }
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
                decoration: BoxDecoration(
                  color: selected == e.key ? const Color(0xFFEAF0FB) : const Color(0xFFE9EEF1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected == e.key ? AppColors.blue : Colors.transparent, width: 1.5),
                ),
                child: Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                      child: Transform.scale(scale: 1.25, child: Image.asset(e.key.asset, fit: BoxFit.contain)),
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
