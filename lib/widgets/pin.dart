import 'dart:async';

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

/// Map pin: tinted teardrop with a marked border, the glyph inside
/// (alternating with the age of the status), the number top-right
/// (no number when the place is full) and a pulsing base dot.
class PlacePin extends StatefulWidget {
  final Place place;
  final bool selected;
  final bool small;
  const PlacePin({super.key, required this.place, this.selected = false, this.small = false});

  static const double width = 64;
  static const double height = 76;

  @override
  State<PlacePin> createState() => _PlacePinState();
}

class _PlacePinState extends State<PlacePin> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  Timer? _swap;
  bool _showAge = false;

  @override
  void initState() {
    super.initState();
    if (!widget.place.type.isNeutral) {
      _swap = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _showAge = !_showAge);
      });
    }
  }

  @override
  void dispose() {
    _swap?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final c = colorsFor(p.shownStatus);
    final scale = widget.selected ? 1.18 : (widget.small ? 0.78 : 1.0);
    final showCount = p.count != null && p.shownStatus != Status.full && !p.type.isNeutral;
    const drop = 38.0;

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
            // pulsing base
            Positioned(
              bottom: 0,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final t = _pulse.value;
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
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.dark,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
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
                        boxShadow: [
                          BoxShadow(color: c.dark.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3)),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _showAge
                        ? Text(p.age.replaceAll(' ', '\n'),
                            key: const ValueKey('age'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 8.5, height: 1.0, fontWeight: FontWeight.w900, color: c.dark))
                        : Glyph(p.type, key: const ValueKey('g'), size: 19, color: c.dark),
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
            if (p.type.isNeutral)
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
