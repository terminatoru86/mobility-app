import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../data/store.dart';
import '../theme.dart';
import '../widgets/sheet_parts.dart';
import '../widgets/signup.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Color _stateColor(double v) => v < 0.55
    ? AppColors.green
    : v < 0.8
        ? AppColors.yellow
        : AppColors.red;

/// Demo values that stay the same for the same place.
double _val(Place p, int a, int b) {
  final h = (p.id.hashCode ^ (a * 7919) ^ (b * 104729)) & 0x7fffffff;
  final peak = 1 - ((b - 15).abs() / 12);
  return ((h % 40) / 100 + peak * 0.6).clamp(0.0, 1.0).toDouble();
}

// ───────────────────────── 3.4b History (occupancy or price) ─────────────────────────

class HistoryScreen extends StatefulWidget {
  final Place place;
  final bool price;
  const HistoryScreen({super.key, required this.place, this.price = false});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _tab = 'Week';
  int _day = DateTime.now().weekday - 1;
  bool _pm = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(widget.price ? 'Price history' : 'Occupancy history'),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(p.address, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'Day', label: Text('Day')),
            const ButtonSegment(value: 'Week', label: Text('Week')),
            if (!widget.price) const ButtonSegment(value: 'Month', label: Text('Month')),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 14),
        if (_tab == 'Day') ..._dayView(p),
        if (_tab == 'Week') ..._weekGrid(p),
        if (_tab == 'Month') ..._monthClocks(p),
      ]),
    );
  }

  List<Widget> _dayView(Place p) {
    final hours = [for (int h = 7; h <= 22; h++) h];
    final vals = [for (final h in hours) _val(p, _day, h)];
    String money(double v) => '\$${(1 + v * 4).round()}';
    return [
      Wrap(spacing: 6, children: [
        for (int i = 0; i < 7; i++)
          ChoiceChip(label: Text(_days[i]), selected: _day == i, onSelected: (_) => setState(() => _day = i)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          SizedBox(
            height: 110,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (int i = 0; i < hours.length; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: 10 + vals[i] * 95,
                    decoration: BoxDecoration(
                      color: _stateColor(vals[i]),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('7', style: TextStyle(fontSize: 10, color: AppColors.soft)),
            Text('10', style: TextStyle(fontSize: 10, color: AppColors.soft)),
            Text('13', style: TextStyle(fontSize: 10, color: AppColors.soft)),
            Text('16', style: TextStyle(fontSize: 10, color: AppColors.soft)),
            Text('19', style: TextStyle(fontSize: 10, color: AppColors.soft)),
            Text('22', style: TextStyle(fontSize: 10, color: AppColors.soft)),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      if (widget.price)
        Text(
          'Cheapest ${money(vals.reduce(math.min))} · now ${money(vals[(DateTime.now().hour - 7).clamp(0, 15)])} · '
          'most expensive ${money(vals.reduce(math.max))}\nWhole day: \$${vals.fold<double>(0, (a, v) => a + 1 + v * 4).round()}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        )
      else
        _confirmations(p),
    ];
  }

  Widget _confirmations(Place p) {
    final cap = 12;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_days[_day]}, confirmation by confirmation', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final h in const [19, 17, 15, 14, 13, 12, 8, 7])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 54,
                child: Text('$h:${(17 * h % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.circle, size: 10, color: _stateColor(_val(p, _day, h))),
              const SizedBox(width: 8),
              Text('${(cap * (1 - _val(p, _day, h))).round()} / $cap',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _stateColor(_val(p, _day, h)))),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _weekGrid(Place p) {
    final hours = [for (int h = 6; h <= 23; h++) h];
    return [
      Text(widget.price ? 'The whole week, by hour' : 'Average of the last 4 weeks',
          style: const TextStyle(color: AppColors.soft)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (int d = 0; d < 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 34, child: Text(_days[d], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                for (final h in hours)
                  Expanded(
                    child: Container(
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 0.6),
                      decoration: BoxDecoration(
                        color: _stateColor(_val(p, d, h)).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 4),
          const Row(children: [
            SizedBox(width: 34),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('6', style: TextStyle(fontSize: 10, color: AppColors.soft)),
                Text('10', style: TextStyle(fontSize: 10, color: AppColors.soft)),
                Text('14', style: TextStyle(fontSize: 10, color: AppColors.soft)),
                Text('18', style: TextStyle(fontSize: 10, color: AppColors.soft)),
                Text('22', style: TextStyle(fontSize: 10, color: AppColors.soft)),
              ]),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        widget.price
            ? 'Cheapest: Sunday and evenings after 8 pm\nMost expensive: Mon–Fri, 10–12 and 4–7 pm'
            : 'Most free: Sunday morning and every day after 8 pm\nBusiest: Mon–Fri, 12–5 pm',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(widget.price ? '🟢 \$1–2   🟡 \$3–4   🔴 \$5 per hour' : '🟢 free   🟡 almost full   🔴 full',
          style: const TextStyle(fontSize: 12)),
    ];
  }

  List<Widget> _monthClocks(Place p) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    return [
      Row(children: [
        Text('${_months[now.month - 1]} ${now.year}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const Spacer(),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('AM')), ButtonSegment(value: true, label: Text('PM'))],
          selected: {_pm},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _pm = s.first),
        ),
      ]),
      const SizedBox(height: 10),
      // days of the week on top, then the month starting under the right weekday
      Row(children: [
        for (final w in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
          Expanded(
            child: Text(w,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.soft)),
          ),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (int i = 1; i < DateTime(now.year, now.month, 1).weekday; i++) const SizedBox.shrink(),
          for (int d = 1; d <= days; d++)
            CustomPaint(size: Size.infinite, painter: _ClockPainter(p, d, _pm, today: d == now.day)),
        ],
      ),
      const SizedBox(height: 8),
      const Text('Each day is a clock with its date in the middle: the coloured arcs sit at the hours riders confirmed (12 top, 3 right). Today has a dark ring.',
          style: TextStyle(fontSize: 12, color: AppColors.soft)),
    ];
  }
}

class _ClockPainter extends CustomPainter {
  final Place p;
  final int day;
  final bool pm;
  final bool today;
  _ClockPainter(this.p, this.day, this.pm, {this.today = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = today ? AppColors.ink : AppColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = today ? 2 : 1);
    // the date in the middle of the clock
    final tp = TextPainter(
      text: TextSpan(
        text: '$day',
        style: TextStyle(
          fontSize: math.max(9, r * 0.62),
          fontWeight: today ? FontWeight.w900 : FontWeight.w700,
          color: today ? AppColors.ink : AppColors.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    for (int k = 0; k < 3; k++) {
      final hour = (day * 3 + k * 4) % 12;
      final v = _val(p, day % 7, hour + (pm ? 12 : 0));
      final start = (hour / 12) * 2 * math.pi - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2.5),
        start,
        0.7,
        false,
        Paint()
          ..color = _stateColor(v)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClockPainter o) => o.pm != pm || o.day != day || o.today != today;
}

// ───────────────────────── 3.4 Reviews ─────────────────────────

class ReviewsScreen extends StatefulWidget {
  final Place place;
  final AppState? state;
  const ReviewsScreen({super.key, required this.place, this.state});
  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  Future<void> _write() async {
    final st = widget.state;
    if (st != null && !st.hasAccount) {
      await showSignupInvite(context, st);
      if (!st.hasAccount || !mounted) return;
    }
    int stars = 5;
    final t = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Write a review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFE0A100), size: 34),
                ),
            ]),
            TextField(
              controller: t,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What should riders know?',
                filled: true,
                fillColor: AppColors.paper,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
              ),
            ),
            FilledButton(
              onPressed: () {
                Store.i.addReview(UserReview(widget.place.id, stars, t.text.trim(), DateTime.now()));
                Navigator.pop(ctx);
              },
              child: const Text('Post review'),
            ),
          ]),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final mine = Store.i.myReviews.where((r) => r.placeId == p.id).toList();
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Reviews')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(p.address, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Row(children: [
          Text(p.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Text('★' * p.rating.round(), style: const TextStyle(color: Color(0xFFE0A100), fontSize: 20)),
          const SizedBox(width: 8),
          Text('${p.reviewCount + mine.length} reviews · newest first', style: const TextStyle(color: AppColors.soft)),
        ]),
        const SizedBox(height: 10),
        for (final r in mine) _card(r.stars, r.text.isEmpty ? '(no text)' : r.text, 'just now', mine: true),
        for (final r in p.reviews) _card(r.stars, r.text, r.when),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _write, icon: const Icon(Icons.edit_outlined), label: const Text('Write a review')),
        const SizedBox(height: 6),
        const Text('Anyone can read reviews; writing needs an account.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ]),
    );
  }

  Widget _card(int stars, String text, String when, {bool mine = false}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: mine ? Border.all(color: AppColors.green, width: 1.5) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('★' * stars + '☆' * (5 - stars), style: const TextStyle(color: Color(0xFFE0A100))),
            const Spacer(),
            Text(when, style: const TextStyle(color: AppColors.soft, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Text(text),
        ]),
      );
}

// ───────────────────────── simple calendar (service and Rent) ─────────────────────────

Future<DateTime?> pickDay(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      selectableDayPredicate: (d) => d.weekday != DateTime.sunday, // closed on Sundays (demo)
    );

String _dayLabel(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final pre = d.day == tomorrow.day && d.month == tomorrow.month ? 'Tomorrow, ' : '';
  return '$pre${m[d.month - 1]} ${d.day}';
}

Widget _field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.soft)),
      const SizedBox(height: 4),
      child,
      const SizedBox(height: 12),
    ]);

Widget _box(String text, {VoidCallback? onTap, IconData icon = Icons.expand_more}) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          Icon(icon, color: AppColors.soft),
        ]),
      ),
    );

// ───────────────────────── 3.4 Service request ─────────────────────────

class ServiceRequestScreen extends StatefulWidget {
  final Place place;
  final AppState? state;
  const ServiceRequestScreen({super.key, required this.place, this.state});
  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  DateTime _day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 14, minute: 0);
  final _note = TextEditingController();
  final _phone = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final vehicle = st?.myVehicle == null
        ? 'Choose in Profile → My vehicle'
        : '${st!.myVehicle!.label}${st.model.isEmpty ? '' : ' · ${st.model}'}';
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Service request')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.place.address, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        if (_sent)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(16)),
            child: const Text('Request sent. We will let you know with a notification.',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.greenDark)),
          )
        else ...[
          _field('Vehicle (from Profile)', _box(vehicle, icon: Icons.pedal_bike)),
          _field(
            'Date and time',
            Row(children: [
              Expanded(
                flex: 3,
                child: _box(_dayLabel(_day), onTap: () async {
                  final d = await pickDay(context, _day);
                  if (d != null) setState(() => _day = d);
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _box(_time.format(context), onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                }),
              ),
            ]),
          ),
          _field(
            'What is wrong? Which parts do you have?',
            TextField(
              controller: _note,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
              ),
            ),
          ),
          _field(
            'Phone (only the service sees it)',
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '(312) 555-0177',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
              ),
            ),
          ),
          FilledButton(onPressed: () => setState(() => _sent = true), child: const Text('Send request')),
        ],
      ]),
    );
  }
}

// ───────────────────────── 3.4 Rent ─────────────────────────

class RentScreen extends StatefulWidget {
  final Place place;
  const RentScreen({super.key, required this.place});
  @override
  State<RentScreen> createState() => _RentScreenState();
}

class _RentScreenState extends State<RentScreen> {
  Vehicle _v = Vehicle.bike;
  DateTime _day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  String _dur = '2 h';
  String _status = '';

  static const _free = {Vehicle.bike: 6, Vehicle.scooter: 3, Vehicle.moped: 2, Vehicle.moto: 1};
  static const _hours = {'2 h': 2, '4 h': 4, '1 day': 8, '3 days': 24};

  @override
  Widget build(BuildContext context) {
    final rate = switch (_v) { Vehicle.moped => 14, Vehicle.moto => 22, Vehicle.scooter => 10, _ => 8 };
    final est = rate * _hours[_dur]!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(backgroundColor: AppColors.paper, title: const Text('Rent')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.place.address, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        if (_status.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.greenTint, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                child: Text('Booking $_status · ${_v.label}, ${_dayLabel(_day)} ${_time.format(context)}, $_dur',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.greenDark)),
              ),
              if (_status == 'active')
                TextButton(onPressed: () => setState(() => _status = 'cancelled'), child: const Text('Cancel')),
            ]),
          ),
        _field(
          'Vehicle',
          RentVehicleRow(free: _free, selected: _v, onTap: (v) => setState(() => _v = v)),
        ),
        _field(
          'Date and time',
          Row(children: [
            Expanded(
              flex: 3,
              child: _box(_dayLabel(_day), onTap: () async {
                final d = await pickDay(context, _day);
                if (d != null) setState(() => _day = d);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _box(_time.format(context), onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              }),
            ),
          ]),
        ),
        _field(
          'Duration',
          Wrap(spacing: 6, children: [
            for (final d in _hours.keys)
              ChoiceChip(label: Text(d), selected: _dur == d, onSelected: (_) => setState(() => _dur = d)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Expanded(child: Text('Estimated price\nset by the shop', style: TextStyle(color: AppColors.soft))),
            Text('~ \$$est', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ]),
        ),
        if (_v == Vehicle.moped || _v == Vehicle.moto)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('🪪 A driving licence is needed for mopeds and motorcycles.',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.yellowDark)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => setState(() => _status = 'active'),
          child: Text('Book the ${_v.label.toLowerCase()}'),
        ),
        const SizedBox(height: 6),
        const Text('You pay at the shop. Cancel from the notification.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.soft)),
      ]),
    );
  }
}
