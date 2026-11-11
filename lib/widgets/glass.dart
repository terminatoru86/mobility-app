import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// White glass: a little over a third white with the map blurred behind it, a hairline of light on the edge
/// and a soft shadow. What sits under it shows as a blur of colour, never through it.
/// One material for the search bar, the weather button, the GPS button and the place sheet.
const kGlass = Color(0x4DFFFFFF); // white at 30 %: the colour of a pin underneath comes through clearly

/// The map behind the glass: blurred, with its colours made stronger so a pin shows as a clear
/// blur of its own colour.
ui.ImageFilter glassFilter() {
  const s = 1.7; // saturation
  const r = 0.2126 * (1 - s), g = 0.7152 * (1 - s), b = 0.0722 * (1 - s);
  return ui.ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    inner: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
  );
}
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

  /// the hairline on the edge (white by default; a colour for a tinted glass)
  final Color line;
  final double lineWidth;

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
    this.line = kGlassLine,
    this.lineWidth = 0.6,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final box = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: r, border: Border.all(color: line, width: lineWidth)),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: kGlassShadow),
      child: ClipRRect(
        borderRadius: r,
        child: blur ? BackdropFilter(filter: glassFilter(), child: box) : box,
      ),
    );
  }
}
