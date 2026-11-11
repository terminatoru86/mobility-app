import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// White glass: about 70 % white with the map blurred behind it, a hairline of light on the edge
/// and a soft shadow. What sits under it shows as a blur of colour, never through it.
/// One material for the search bar, the weather button, the GPS button and the place sheet.
const kGlass = Color(0xB3FFFFFF); // white at 70 %
const kGlassLine = Color(0xCCFFFFFF);
const kGlassShadow = [BoxShadow(color: Color(0x1A0F1E24), blurRadius: 8, offset: Offset(0, 2))];

/// The height of every control on the map: search bar, weather, GPS, +, SOS.
const double kCtl = 48;

/// The distance from the screen edge to every control on the map.
const double kEdge = 8;

class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double? width, height;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// false: no blur behind (lighter to draw; used where many small pieces sit side by side)
  final bool blur;
  const Glass({
    super.key,
    required this.child,
    this.radius = kCtl / 2,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.color = kGlass,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final box = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: r, border: Border.all(color: kGlassLine, width: 0.6)),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: kGlassShadow),
      child: ClipRRect(
        borderRadius: r,
        child: blur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9), child: box) : box,
      ),
    );
  }
}
