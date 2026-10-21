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

/// One shared clock for all pins: glyph and age take turns every 4 s.
/// (One timer for the whole map instead of one per pin keeps the map fast.)
final ValueNotifier<bool> pinShowsAge = ValueNotifier(false);

/// Map pin: solid teardrop in the status colour with a white edge and a shadow
/// (easy to see on the grey map), the white glyph inside
/// (alternating with the age of the status), the number top-right
/// (no number when the place is full). Only the selected pin pulses.
class PlacePin extends StatelessWidget {
  final Place place;
  final bool selected;
  final bool small;
  const PlacePin({super.key, required this.place, this.selected = false, this.small = false});

  static const double width = 64;
  static const double height = 76;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final c = colorsFor(p.shownStatus);
    final scale = selected ? 1.2 : (small ? 0.9 : 1.05);
    final showCount = p.count != null && p.shownStatus != Status.full && !p.type.isNeutral;
    final swaps = !p.type.isNeutral && p.age.isNotEmpty;
    const drop = 40.0;
    // white on green / red / grey; dark brown on yellow so it stays readable
    final ink = p.shownStatus == Status.almost ? const Color(0xFF3A2A00) : Colors.white;
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
            // base dot (pulses only when selected)
            Positioned(bottom: 0, child: selected ? _Pulse(color: c) : _BaseDot(c)),
            // teardrop
            Positioned(
              top: 8,
              child: SizedBox(
                width: drop,
                height: drop,
                child: Stack(alignment: Alignment.center, children: [
                  Transform.rotate(
                    angle: -0.785398, // -45°
                    child: Container(
                      width: drop - 6,
                      height: drop - 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [Color.lerp(c.main, Colors.white, 0.18)!, c.main, Color.lerp(c.main, c.dark, 0.35)!],
                        ),
                        border: Border.all(color: Colors.white, width: 2.5),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(40),
                          topRight: Radius.circular(40),
                          bottomRight: Radius.circular(40),
                        ),
                        boxShadow: [
                          BoxShadow(color: c.dark.withValues(alpha: 0.45), blurRadius: 6, offset: const Offset(-2, 3)),
                          const BoxShadow(color: Color(0x33000000), blurRadius: 1.5, spreadRadius: 0.5),
                        ],
                      ),
                    ),
                  ),
                  if (!swaps)
                    glyph
                  else
                    ValueListenableBuilder<bool>(
                      valueListenable: pinShowsAge,
                      builder: (_, showAge, __) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: showAge
                            ? Text(p.age.replaceAll(' ', '\n'),
                                key: const ValueKey('age'),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 9, height: 1.0, fontWeight: FontWeight.w900, color: ink))
                            : glyph,
                      ),
                    ),
                ]),
              ),
            ),
            // number top-right (no circle) or rating badge for neutral places
            // the number alone, no circle: dark status colour with a white outline
            if (showCount)
              Positioned(
                top: -2,
                right: 3,
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
            if (p.type.isNeutral && p.reviewCount > 0)
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
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 16,
        child: Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.main,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 2)],
            ),
          ),
        ),
      );
}

class _Pulse extends StatefulWidget {
  final StatusColors color;
  const _Pulse({required this.color});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) {
        final t = _a.value;
        return SizedBox(
          width: 40,
          height: 16,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 14 + 24 * t,
              height: 6 + 8 * t,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: c.main.withValues(alpha: 0.35 * (1 - t)),
              ),
            ),
            child!,
          ]),
        );
      },
      child: _BaseDot(c),
    );
  }
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
