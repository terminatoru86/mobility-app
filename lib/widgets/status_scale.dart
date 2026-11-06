import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';

/// Which status the map shows as pins (null: all). Set by [StatusScale], read by the map.
final ValueNotifier<Status?> statusFilter = ValueNotifier(null);

/// Colour scale sitting on the top edge of the main menu (map only):
/// a thin line white · red · yellow · green · grey, the values written just above it
/// (All · 0 · 1–2 · 1–4 · 0). The chosen one is a small pill whose tip points into the line.
/// Tap or slide along it to choose; places with another status stay on the map as small dots.
class StatusScale extends StatelessWidget {
  const StatusScale({super.key});

  static const _stops = <(Status?, String, Color, Color)>[
    // status, label, line colour, text colour
    (null, 'All', Colors.white, AppColors.ink),
    (Status.full, '0', AppColors.red, AppColors.redDark),
    (Status.almost, '1–2', AppColors.yellow, AppColors.yellowDark),
    (Status.free, '1–4', AppColors.green, AppColors.greenDark),
    (Status.unknown, '0', AppColors.grey, AppColors.greyDark),
  ];

  static const double height = 28;
  static const double _line = 5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final seg = box.maxWidth / _stops.length;
      void pick(double x) {
        final i = (x / seg).floor().clamp(0, _stops.length - 1);
        final s = _stops[i].$1;
        if (statusFilter.value != s) statusFilter.value = s;
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
        child: ValueListenableBuilder<Status?>(
          valueListenable: statusFilter,
          builder: (_, cur, __) {
            final sel = _stops.indexWhere((e) => e.$1 == cur);
            return SizedBox(
              height: height,
              child: Stack(clipBehavior: Clip.none, children: [
                // the thin colour line = the top edge of the menu
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _line,
                  child: Row(children: [
                    for (final s in _stops)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: s.$3,
                            border: s.$1 == null
                                ? const Border(top: BorderSide(color: AppColors.line, width: 0.8))
                                : null,
                          ),
                        ),
                      ),
                  ]),
                ),
                // the values just above the line; the chosen one as a pill pointing into it
                for (var k = 0; k < _stops.length; k++)
                  Positioned(
                    left: seg * k,
                    width: seg,
                    // the pill's tip goes all the way into the line
                    bottom: k == sel ? 0 : _line - 1,
                    child: Center(
                      child: k == sel ? _Chosen(_stops[k]) : _Plain(_stops[k]),
                    ),
                  ),
              ]),
            );
          },
        ),
      );
    });
  }
}

class _Plain extends StatelessWidget {
  final (Status?, String, Color, Color) s;
  const _Plain(this.s);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(s.$2,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w800,
              color: s.$4,
              shadows: const [
                Shadow(color: Colors.white, blurRadius: 3),
                Shadow(color: Colors.white, blurRadius: 1.5),
              ],
            )),
      );
}

class _Chosen extends StatelessWidget {
  final (Status?, String, Color, Color) s;
  const _Chosen(this.s);
  @override
  Widget build(BuildContext context) {
    final fill = s.$1 == null ? AppColors.ink : s.$3;
    final ink = s.$1 == Status.almost ? AppColors.yellowDark : Colors.white;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Text(s.$2, style: TextStyle(fontSize: 12.5, height: 1, fontWeight: FontWeight.w900, color: ink)),
      ),
      // the tip, pointing down into the line
      CustomPaint(size: const Size(12, 6), painter: _Tip(fill)),
    ]);
  }
}

class _Tip extends CustomPainter {
  final Color c;
  _Tip(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _Tip old) => old.c != c;
}
