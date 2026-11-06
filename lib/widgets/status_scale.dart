import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';

/// Which status the map shows as pins (null: all). Set by [StatusScale], read by the map.
final ValueNotifier<Status?> statusFilter = ValueNotifier(null);

/// Thin colour scale above the main menu: All (white) · red 0 · yellow 1–2 · green 1–4 · grey 0.
/// The small arrow points at the chosen colour; tap or slide along it to choose.
/// The places with another status stay on the map as small dots.
class StatusScale extends StatelessWidget {
  const StatusScale({super.key});

  static const _stops = <(Status?, String)>[
    (null, 'All'),
    (Status.full, '0'),
    (Status.almost, '1–2'),
    (Status.free, '1–4'),
    (Status.unknown, '0'),
  ];

  @override
  Widget build(BuildContext context) {
    // the top edge of the main menu: full width, no padding, no frame (it sits on the menu, not in it)
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final seg = w / _stops.length;
      void pick(double x) {
        final i = (x / seg).floor().clamp(0, _stops.length - 1);
        final s = _stops[i].$1;
        if (statusFilter.value != s) statusFilter.value = s;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
        child: ValueListenableBuilder<Status?>(
          valueListenable: statusFilter,
          builder: (_, cur, __) {
            final i = _stops.indexWhere((e) => e.$1 == cur);
            return SizedBox(
              height: 14,
              child: Stack(clipBehavior: Clip.none, children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.symmetric(horizontal: BorderSide(color: AppColors.line, width: 0.8)),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white, Colors.white, // All
                          AppColors.red, AppColors.red, // 0
                          AppColors.yellow, AppColors.yellow, // 1–2
                          AppColors.green, AppColors.green, // 1–4
                          AppColors.grey, AppColors.grey, // 0
                        ],
                        stops: [0, .17, .23, .37, .43, .57, .63, .77, .83, 1],
                      ),
                    ),
                  ),
                ),
                for (var k = 0; k < _stops.length; k++)
                  Positioned(
                    left: seg * k,
                    width: seg,
                    top: 0,
                    bottom: 1.5,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text(_stops[k].$2,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1,
                            fontWeight: k == i ? FontWeight.w900 : FontWeight.w700,
                            color: k == 0 || k == 2 ? AppColors.ink : Colors.white,
                          )),
                    ),
                  ),
                // the black arrow, deep in the bar over the chosen colour
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: seg * (i < 0 ? 0 : i) + seg / 2 - 5,
                  top: -2,
                  child: CustomPaint(size: const Size(10, 9), painter: _Arrow()),
                ),
              ]),
            );
          },
        ),
      );
    });
  }
}

class _Arrow extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
