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

/// Map pin: tinted teardrop with a marked border, the glyph inside
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
    final scale = selected ? 1.18 : (small ? 0.78 : 1.0);
    final showCount = p.count != null && p.shownStatus != Status.full && !p.type.isNeutral;
    final swaps = !p.type.isNeutral && p.age.isNotEmpty;
    const drop = 38.0;
    final glyph = Glyph(p.type, key: const ValueKey('g'), size: 19, color: c.dark);

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
                        color: c.tint,
                        border: Border.all(color: c.main, width: 2.5),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(40),
                          topRight: Radius.circular(40),
                          bottomRight: Radius.circular(40),
                        ),
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
                                style: TextStyle(fontSize: 8.5, height: 1.0, fontWeight: FontWeight.w900, color: c.dark))
                            : glyph,
                      ),
                    ),
                ]),
              ),
            ),
            // number top-right (no circle) or rating badge for neutral places
            if (showCount)
              Positioned(
                top: 0,
                right: 4,
                child: Text(p.count!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: c.dark,
                      shadows: const [Shadow(color: Colors.white, blurRadius: 3), Shadow(color: Colors.white, blurRadius: 3)],
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
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.dark,
              border: Border.all(color: Colors.white, width: 1.5),
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
