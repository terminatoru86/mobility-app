import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';

/// Which status the map shows as pins (null: all). Set by [StatusScale], read by the map.
final ValueNotifier<Status?> statusFilter = ValueNotifier(null);

/// Thin colour bar on the top edge of the main menu (map only), drawn like the pins:
/// each colour is a light tint with an edge in the status colour; the chosen one is filled
/// with its colour and a small arrow sits inside it. No text.
/// Order: All (white) · red · yellow · green · grey. Tap or slide to choose; the places with
/// another status stay on the map as small dots.
class StatusScale extends StatelessWidget {
  const StatusScale({super.key});

  static const _stops = <(Status?, Color, Color, Color)>[
    // status, edge, tint, dark (arrow)
    (null, AppColors.slate, Colors.white, AppColors.ink),
    (Status.full, AppColors.red, AppColors.redTint, AppColors.redDark),
    (Status.almost, AppColors.yellow, AppColors.yellowTint, AppColors.yellowDark),
    (Status.free, AppColors.green, AppColors.greenTint, AppColors.greenDark),
    (Status.unknown, AppColors.grey, AppColors.greyTint, AppColors.greyDark),
  ];

  /// Touch area (the bar itself is [_bar] high, at the bottom of it).
  static const double height = 16;
  static const double _bar = 7;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final seg = box.maxWidth / _stops.length;
      void pick(double x) {
        final s = _stops[(x / seg).floor().clamp(0, _stops.length - 1)].$1;
        if (statusFilter.value != s) statusFilter.value = s;
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
        child: SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<Status?>(
              valueListenable: statusFilter,
              builder: (_, cur, __) => SizedBox(
                height: _bar,
                child: Row(children: [
                  for (final s in _stops)
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: s.$1 == cur ? s.$2 : s.$3,
                          border: Border(top: BorderSide(color: s.$2, width: 1.5)),
                        ),
                        child: s.$1 == cur
                            // the small arrow, inside the chosen colour (it does not stick out)
                            ? Center(
                                child: CustomPaint(
                                  size: const Size(9, 5),
                                  painter: _Arrow(s.$1 == null ? Colors.white : s.$4),
                                ),
                              )
                            : null,
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Arrow extends CustomPainter {
  final Color c;
  _Arrow(this.c);
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
  bool shouldRepaint(covariant _Arrow old) => old.c != c;
}
