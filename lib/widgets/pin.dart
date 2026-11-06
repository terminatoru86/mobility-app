import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/places.dart';
import '../theme.dart';

/// Glyph of a place type, tinted with [color].
class Glyph extends StatelessWidget {
  final PlaceType type;
  final double size;
  final Color color;
  const Glyph(this.type, {super.key, this.size = 22, this.color = AppColors.ink});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        type.glyph,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// One shared clock for all pins: glyph and age take turns every 8 s (only pins on screen, only coloured ones).
/// (One timer for the whole map instead of one per pin keeps the map fast.)
final ValueNotifier<bool> pinShowsAge = ValueNotifier(false);

/// How much a pin shows, by zoom (see map_screen `_detail`):
///  full  – zoomed in, street names readable: glyph and age take turns; shops/service/rent/BMX show their rating
///  glyph – a bit further out: only the glyph (nothing turns, no rating)
///  count – further out: only the coloured pin with the number of free places (no glyph)
/// (further out still, pins that touch become groups)
enum PinDetail { full, glyph, count }

/// Map pin: solid teardrop in the status colour with a white edge and a shadow
/// (easy to see on the grey map), the white glyph inside
/// (alternating with the age of the status), the number top-right
/// (no number when the place is full). Only the selected pin pulses.
class PlacePin extends StatelessWidget {
  final Place place;
  final bool selected;
  final bool small;

  /// false: the pin is outside the screen, it does not take turns (keeps the map light)
  final bool animate;
  final PinDetail detail;
  const PlacePin(
      {super.key,
      required this.place,
      this.selected = false,
      this.small = false,
      this.animate = true,
      this.detail = PinDetail.full,
      this.showRating = true});

  /// the rating badge (shops, service, rent, BMX): only close in, where street names are readable
  final bool showRating;

  static const double width = 64;
  static const double height = 58; // the bottom is the map point (centre of the ball)

  @override
  Widget build(BuildContext context) {
    final p = place;
    final c = colorsFor(p.shownStatus);
    final scale = selected ? 1.2 : (small ? 0.9 : 1.05);
    final hasCount = p.count != null && p.shownStatus != Status.full && !p.type.isNeutral;
    final countOnly = detail == PinDetail.count && !selected;
    // the number top-right only close in, together with the time; further out it sits inside the pin
    final showCount = hasCount && (detail == PinDetail.full || selected);
    // grey pins (no status yet, shops, service) show only the glyph: no time, nothing turning
    final grey = p.shownStatus == Status.unknown || p.shownStatus == Status.neutral;
    final full = detail == PinDetail.full || selected;
    final swaps = full && animate && !grey && !p.type.isNeutral && p.age.isNotEmpty;
    // manual design: drawing and time in the dark tone of the status, on the tinted inside
    final ink = c.dark;
    final glyph = Glyph(p.type, key: const ValueKey('g'), size: 20, color: ink);

    return SizedBox(
      width: PlacePin.width,
      height: PlacePin.height,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // the ball on the map point: small, right under the tip
            Positioned(bottom: -3.5, child: _BaseDot(c)),
            // the pin: round head, sharp point down to the ball
            Positioned(
              top: 4,
              child: SizedBox(
                width: _PinShape.w,
                height: _PinShape.h,
                child: Stack(alignment: Alignment.topCenter, children: [
                  Positioned.fill(child: CustomPaint(painter: _PinShape(c))),
                  Positioned(
                    top: _PinShape.cy - 13,
                    height: 26,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: countOnly
                          ? (hasCount
                              ? Text(p.count!,
                                  style: TextStyle(fontSize: 14, height: 1.0, fontWeight: FontWeight.w900, color: ink))
                              : const SizedBox.shrink())
                          : !swaps
                              ? glyph
                              : ValueListenableBuilder<bool>(
                                  valueListenable: pinShowsAge,
                                  builder: (_, showAge, __) => AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: showAge
                                        ? Text(p.age.replaceAll(' ', '\n'),
                                            key: const ValueKey('age'),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 9, height: 1.0, fontWeight: FontWeight.w900, color: ink))
                                        : glyph,
                                  ),
                                ),
                    ),
                  ),
                ]),
              ),
            ),
            // number top-right (no circle) or rating badge for neutral places
            // the number alone, no circle: dark status colour with a white outline
            if (showCount)
              // stuck to the top-right edge of the pin (manual: just outside the corner)
              // anchored at its left side on the pin edge: every number touches the line, like "2/4" at charging
              Positioned(
                top: 0,
                left: 44,
                child: Text(p.count!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: c.dark,
                      shadows: const [
                        Shadow(color: Colors.white, offset: Offset(1.2, 0)),
                        Shadow(color: Colors.white, offset: Offset(-1.2, 0)),
                        Shadow(color: Colors.white, offset: Offset(0, 1.2)),
                        Shadow(color: Colors.white, offset: Offset(0, -1.2)),
                        Shadow(color: Colors.white, blurRadius: 3),
                      ],
                    )),
              ),
            if (full && showRating && p.type.isNeutral && p.reviewCount > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.slate,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text('${p.rating.toStringAsFixed(1)}★',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BaseDot extends StatelessWidget {
  final StatusColors c;
  const _BaseDot(this.c);
  // a small ball in the status colour (white light top-left, darker below) exactly on the map point
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4),
            radius: 0.85,
            colors: [Color.lerp(c.main, Colors.white, 0.65)!, c.main, c.dark],
            stops: const [0, 0.5, 1],
          ),
        ),
      );
}

/// The pin outline: a round head and a sharp point (tangent lines to the tip).
/// Inside: white light top-right, the status tint; edge in the status colour; a soft shadow.
class _PinShape extends CustomPainter {
  final StatusColors c;
  _PinShape(this.c);
  static const double w = 38, h = 50, r = 16.5, cy = 18;

  static Path _path() {
    const cx = w / 2, tipY = h - 1;
    final d = tipY - cy; // centre to tip
    final a = math.asin(r / d); // half-angle of the point
    final t = math.pi / 2 - a; // tangent point angle from the downward axis
    final path = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - r * math.sin(t), cy + r * math.cos(t))
      ..arcTo(Rect.fromCircle(center: const Offset(cx, cy), radius: r), math.pi / 2 + t, 2 * (math.pi - t), false)
      ..close();
    return path;
  }

  static final Path _shape = _path();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(_shape, c.dark.withValues(alpha: 0.6), 2.5, false);
    canvas.drawPath(
      _shape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, -0.55),
          radius: 0.9,
          colors: [Colors.white, c.tint, Color.lerp(c.tint, c.main, 0.2)!],
          stops: const [0, 0.55, 1],
        ).createShader(const Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      _shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = c.main,
    );
  }

  @override
  bool shouldRepaint(covariant _PinShape old) => old.c != c;
}

/// Small coloured "you are here" dot.
class UserDot extends StatelessWidget {
  const UserDot({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.blue.withValues(alpha: 0.18)),
        alignment: Alignment.center,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.blue,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      );
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Traffic light, stop sign or give-way sign (drawn, so they look the same everywhere).
class TrafficControlIcon extends StatelessWidget {
  final String kind; // 'signals', 'stop', 'give_way'
  final double size;
  const TrafficControlIcon({super.key, required this.kind, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final svg = switch (kind) {
      'stop' => '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M7.6 1.5h8.8l6.1 6.1v8.8l-6.1 6.1H7.6l-6.1-6.1V7.6Z" fill="#D7262E" stroke="#fff" stroke-width="1.2"/>'
          '<text x="12" y="14.6" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-weight="900" '
          'font-size="6.6" fill="#fff">STOP</text></svg>',
      'give_way' => '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M2 3.5h20L12 21.5Z" fill="#fff" stroke="#D7262E" stroke-width="2.6" stroke-linejoin="round"/></svg>',
      _ => '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="7" y="1" width="10" height="22" rx="3.2" fill="#13212B"/>'
          '<circle cx="12" cy="5.6" r="2.4" fill="#E0484D"/><circle cx="12" cy="12" r="2.4" fill="#E9A800"/>'
          '<circle cx="12" cy="18.4" r="2.4" fill="#5D9A30"/></svg>',
    };
    return SvgPicture.string(svg, width: size, height: size);
  }
}

/// Map tab icon: a folded map with a location pin standing on it.
class MapTabIcon extends StatelessWidget {
  final Color color;
  final double size;
  const MapTabIcon({super.key, this.color = const Color(0xFF55666F), this.size = 26});

  @override
  Widget build(BuildContext context) {
    final c = _hex(color);
    return SvgPicture.string(
      '<svg viewBox="0 0 26 26" xmlns="http://www.w3.org/2000/svg">'
      // folded map: three panels, the middle one lighter
      '<path d="M2 15.6 8.4 13.4 8.4 23.6 2 25.8Z" fill="$c"/>'
      '<path d="M9.4 13.4 16.6 15.6 16.6 25.8 9.4 23.6Z" fill="$c" fill-opacity=".55"/>'
      '<path d="M17.6 15.6 24 13.4 24 23.6 17.6 25.8Z" fill="$c"/>'
      // the pin, with a white ring to stand out from the map
      '<path d="M15.6 1.2a6.2 6.2 0 0 0-6.2 6.2c0 4.6 6.2 11 6.2 11s6.2-6.4 6.2-11a6.2 6.2 0 0 0-6.2-6.2Z" '
      'fill="$c" stroke="#fff" stroke-width="1.6"/>'
      '<circle cx="15.6" cy="7.4" r="2.3" fill="#fff"/></svg>',
      width: size,
      height: size,
    );
  }
}

/// Small road with a dashed middle line: "there is bike road on this route".
class BikeRoadIcon extends StatelessWidget {
  final double size;
  final Color color;
  const BikeRoadIcon({super.key, this.size = 18, this.color = const Color(0xFF7C8A91)});

  @override
  Widget build(BuildContext context) {
    final c = _hex(color);
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M8.6 4.5 5.4 20M15.4 4.5 18.6 20" stroke="$c" stroke-width="2.3" stroke-linecap="round" fill="none"/>'
      '<path d="M12 5v2M12 11v2M12 17v2.4" stroke="$c" stroke-width="2.3" stroke-linecap="round" fill="none"/></svg>',
      width: size,
      height: size,
    );
  }
}

/// Grey map pin standing on a ring: the destination.
class DestinationPinIcon extends StatelessWidget {
  final double size;
  final Color color;
  const DestinationPinIcon({super.key, this.size = 22, this.color = const Color(0xFF7C8A91)});

  @override
  Widget build(BuildContext context) {
    final c = _hex(color);
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
      '<circle cx="12" cy="6.2" r="3.9" fill="$c"/><circle cx="12" cy="5.6" r="1.15" fill="#fff"/>'
      '<rect x="11" y="9.6" width="2" height="7.6" rx="1" fill="$c"/>'
      '<ellipse cx="12" cy="19.4" rx="6.3" ry="2.5" fill="none" stroke="$c" stroke-width="1.9"/></svg>',
      width: size,
      height: size,
    );
  }
}
