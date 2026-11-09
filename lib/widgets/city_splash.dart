import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../data/places.dart';
import '../theme.dart';
import 'pin.dart';

/// The start screen, only for people without an account (once signed in, the app opens
/// straight on the working map). One still picture, no motion: the city with our pins, the
/// riders and your blue route to the green pin, over the whole screen; in the middle the "m" logo (the same one, in the
/// same place, as Android's own start, so nothing jumps) and MOBIlity under it; at the bottom one
/// short line and our vehicles. It is drawn in the very first frame (Android's logo stays until then).
/// When it ends (main.dart) it fades out over the working map and the sign-in pop-up comes.
class CitySplash extends StatelessWidget {
  const CitySplash({super.key});

  @override
  Widget build(BuildContext context) {
    final img = _startImage;
    if (img == null) return const SplashArt(); // the picture file could not be read: draw it
    return ColoredBox(
      color: const Color(0xFFF1F4F6),
      child: SizedBox.expand(child: RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
    );
  }
}

/// The start picture as a file (made from [SplashArt] on GitHub, see preview/). The same picture
/// is Android's own start background, so it shows at once and nothing changes when Flutter starts.
const String kStartPicture = 'assets/splash/start.jpg';
ui.Image? _startImage;

/// Reads the start picture before the first frame (only when the start screen will show).
Future<void> loadStartPicture() async {
  try {
    final data = await rootBundle.load(kStartPicture);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    _startImage = (await codec.getNextFrame()).image;
  } catch (_) {}
}

/// The start picture, drawn: the city, pins, riders, route, the logo and MOBIlity, the line and
/// the vehicles. Used to make [kStartPicture] (and if that file is missing).
class SplashArt extends StatefulWidget {
  const SplashArt({super.key});
  @override
  State<SplashArt> createState() => _CitySplashState();
}

/// The line on the start screen, above the vehicles.
const String kSplashLine = 'Ride in. Park easy.';

/// The logo's size on the start screen (Android's own start draws it the same size, in the middle).
const double kSplashLogo = 170;


/// Map units → screen (before the 3D camera): an isometric grid, 3 units per block.
class _Geo {
  final double w, h, s, cx, cy;
  _Geo(this.w, this.h)
      : s = w / 11.3,
        cx = w / 2,
        cy = h * 0.46 - 4.2 * (w / 11.3);
  Offset p(double x, double y, [double z = 0]) => Offset(cx + (x - y) * .866 * s, cy + (x + y) * .5 * s - z * s);
}

/// Your route along the streets, to the green spot at the end.
const _route = [Offset(0, 6), Offset(3, 6), Offset(3, 3), Offset(6, 3), Offset(6, 1.5)];

/// Pins on the streets: x, y, the place (type, status, number).
final List<(double, double, Place)> _pins = [
  (1.5, 3, _place('a', PlaceType.rack, Status.full, '0')),
  (6, 4.5, _place('b', PlaceType.parkCovered, Status.almost, '1')),
  (6, 1.5, _place('c', PlaceType.rack, Status.free, '4')),
  (9, 7.5, _place('d', PlaceType.parkOutdoor, Status.free, '6')),
  (4.5, 9, _place('e', PlaceType.charging, Status.free, '2')),
  (-1.5, 6, _place('f', PlaceType.rack, Status.free, '3')),
  (0, 1.5, _place('g', PlaceType.parkOutdoor, Status.almost, '1')),
  (9, 1.5, _place('h', PlaceType.charging, Status.full, '0')),
  (7.5, 9, _place('i', PlaceType.rack, Status.free, '5')),
  (3, 10.5, _place('j', PlaceType.parkCovered, Status.free, '2')),
  (10.5, 4.5, _place('k', PlaceType.rack, Status.free, '3')),
  (-1.5, 9, _place('l', PlaceType.rack, Status.almost, '1')),
  // more pins all over the picture: at the top and in the corners
  (-3, -1.5, _place('m', PlaceType.rack, Status.free, '5')),
  (-1.5, -3, _place('n', PlaceType.parkOutdoor, Status.almost, '2')),
  (1.5, -3, _place('o', PlaceType.charging, Status.free, '3')),
  (-1.5, 0, _place('p', PlaceType.rack, Status.free, '6')),
  (3, -1.5, _place('q', PlaceType.rack, Status.full, '0')),
  (10.5, 6, _place('r', PlaceType.rack, Status.free, '2')),
  (10.5, 12, _place('s', PlaceType.parkOutdoor, Status.free, '4')),
  (13.5, 9, _place('t', PlaceType.parkCovered, Status.free, '3')),
  (15, 10.5, _place('u', PlaceType.charging, Status.almost, '1')),
];
const _arriveAt = 2; // index of the green pin you ride to

Place _place(String id, PlaceType type, Status status, String count) => Place(
      id: 'splash_$id',
      type: type,
      address: '',
      pos: const LatLng(0, 0),
      status: status,
      count: count,
      distance: '',
      etaMin: const {},
    );

/// The other riders: vehicle, from, to (map units, on the streets).
const _riders = <(_Veh, Offset, Offset)>[
  (_Veh.scooter, Offset(3, 0.6), Offset(0.6, 0)),
  (_Veh.moped, Offset(9, 5.6), Offset(9, 3)),
  (_Veh.moto, Offset(7.6, 9), Offset(4.6, 9)),
  (_Veh.bike, Offset(-1.5, 2.6), Offset(-1.5, 7.4)),
];

class _CitySplashState extends State<SplashArt> {

  /// The drawn area: bigger than the screen, so the tilted map never shows an edge.
  static Rect _area(double w, double h) => Rect.fromLTRB(-0.6 * w, -1.5 * h, 1.6 * w, 1.3 * h);

  /// The 3D camera: perspective and tilt over the flat city (the last view of the old film).
  static Matrix4 _camera(double w, double h) {
    const tilt = 0.58, zoom = 1.40;
    final po = Offset(w / 2, h * 0.30), to = Offset(w / 2, h * 0.55);
    return Matrix4.identity()
      ..translate(po.dx, po.dy)
      ..multiply(Matrix4.identity()..setEntry(3, 2, -1 / (2.53 * w)))
      ..translate(to.dx - po.dx, to.dy - po.dy)
      ..rotateX(tilt)
      ..scale(zoom, zoom, 1)
      ..translate(-to.dx, -to.dy);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final g = _Geo(w, h);
        final m = _camera(w, h);
        final area = _area(w, h);
        Offset screen(double x, double y) => MatrixUtils.transformPoint(m, g.p(x, y));
        final pins = <(Offset, int)>[
          for (var i = 0; i < _pins.length; i++) (screen(_pins[i].$1, _pins[i].$2), i),
        ]..sort((a, b) => a.$1.dy.compareTo(b.$1.dy));
        return Stack(fit: StackFit.expand, children: [
          // the whole screen is the city (drawn in the very first frame, Android's logo stays until then)
          RepaintBoundary(
                child: Stack(fit: StackFit.expand, children: [
                  // the city a little to the left, so the route and the green pin sit well inside
                  Transform.translate(
                    offset: Offset(-0.13 * w, 0.02 * h),
                    child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                  Transform(
                    transform: m,
                    filterQuality: FilterQuality.medium,
                    child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                      Positioned(
                        left: area.left,
                        top: area.top,
                        width: area.width,
                        height: area.height,
                        child: CustomPaint(painter: _CityOnce(g, area)),
                      ),
                      CustomPaint(painter: _RoutePainter(g, 1, 1)),
                    ]),
                  ),
                  // the same pins as on the app map; the one you ride to stays bright
                  for (final (pt, i) in pins)
                    Builder(builder: (_) {
                      final place = _pins[i].$3;
                      final depth = (0.48 + 0.34 * (pt.dy / h)).clamp(0.45, 0.85);
                      final dim = i != _arriveAt ? 0.8 : 1.0;
                      final full = place.status == Status.full ? 0.7 : 1.0;
                      return Positioned(
                        left: pt.dx - PlacePin.width / 2,
                        top: pt.dy - PlacePin.height,
                        child: Opacity(
                          opacity: dim * full,
                          child: Transform.scale(
                            scale: depth,
                            alignment: Alignment.bottomCenter,
                            child: PlacePin(place: place, animate: false, detail: PinDetail.full, showRating: false),
                          ),
                        ),
                      );
                    }),
                  // the riders, and you at the end of your route
                  CustomPaint(
                    painter: _RiderPainter(
                      t: 1,
                      show: 1,
                      me: _routePoint(1, screen),
                      others: [for (final (v, _, b) in _riders) (v, screen(b.dx, b.dy))],
                    ),
                  ),
                    ]),
                  ),
                ]),
              ),
          _Title(h: h),
        ]);
      }),
    );
  }

  /// Where you are on your route (screen), [f] 0..1 of its length.
  static Offset _routePoint(double f, Offset Function(double, double) screen) {
    final pts = _route.map((p) => screen(p.dx, p.dy)).toList();
    final path = Path()..addPolygon(pts, false);
    for (final metric in path.computeMetrics()) {
      return metric.getTangentForOffset(metric.length * f)!.position;
    }
    return pts.first;
  }
}


/// The city, painted once (it does not move).
class _CityOnce extends CustomPainter {
  final _Geo g;
  final Rect area;
  _CityOnce(this.g, this.area);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-area.left, -area.top);
    _CityPainter(g).drawCity(canvas, area);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CityOnce o) => o.area != area;
}

/// On top of the map: a soft white glow; exactly in the middle the "m" logo and MOBIlity under
/// it; at the bottom one short line and our four vehicles.
class _Title extends StatelessWidget {
  final double h;
  const _Title({required this.h});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.06),
              radius: 0.62,
              colors: [Color(0xE6FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
              stops: [0, .45, 1],
            ),
          ),
        ),
        // a soft white behind the line and the vehicles at the bottom
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xCCFFFFFF)],
              stops: [0, .76, .93],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: h / 2 - kSplashLogo / 2,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SvgPicture.asset('assets/brand/logo_m.svg', width: kSplashLogo, height: kSplashLogo),
            const SizedBox(height: 2),
            const Text('MOBIlity',
                style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: 0.5)),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 46 + bottom,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(kSplashLine,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.soft, letterSpacing: 0.2)),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final v in _Veh.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CustomPaint(size: const Size(32, 32), painter: _VehPainter(v, AppColors.soft, 1.5)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}


enum _Veh { bike, scooter, moped, moto }

/// Our vehicle line icons (24 x 24 units): bike, kick scooter, moped (Vespa style), motorcycle.
Path _vehPath(_Veh v) {
  final p = Path();
  void c(double x, double y, double r) => p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
  switch (v) {
    case _Veh.bike:
      c(5, 17, 4);
      c(19, 17, 4);
      c(12, 17, 1);
      p
        ..moveTo(5, 17)
        ..lineTo(10, 10.5)
        ..lineTo(12, 17)
        ..close()
        ..moveTo(10, 10.5)
        ..lineTo(16.2, 10.5)
        ..lineTo(12, 17)
        ..moveTo(16.2, 10.5)
        ..lineTo(19, 17)
        ..moveTo(16.2, 10.5)
        ..lineTo(15.4, 7.4)
        ..lineTo(18, 7.4)
        ..moveTo(10, 10.5)
        ..lineTo(9.4, 8)
        ..moveTo(7.9, 8)
        ..lineTo(11, 8);
    case _Veh.scooter:
      c(5, 18.5, 2.6);
      c(19, 18.5, 2.6);
      p
        ..moveTo(5.5, 16.2)
        ..lineTo(14.5, 16.2)
        ..quadraticBezierTo(16, 16.2, 16.8, 14.8)
        ..moveTo(19, 18.5)
        ..lineTo(16.2, 5)
        ..moveTo(14.6, 5)
        ..lineTo(18, 5);
    case _Veh.moped:
      c(5.6, 18, 2.9);
      c(18.6, 18, 2.9);
      p
        ..addPath(_vehFill(v)!, Offset.zero)
        ..moveTo(10.4, 15.8)
        ..lineTo(14.4, 15.8)
        ..lineTo(16.4, 9)
        ..cubicTo(17.8, 11.5, 18.5, 13.5, 18.6, 15)
        ..moveTo(4.8, 10.4)
        ..quadraticBezierTo(7.2, 9.4, 9.8, 10.4)
        ..moveTo(16.4, 9)
        ..lineTo(16.9, 6)
        ..moveTo(15.3, 6)
        ..lineTo(18.6, 6);
    case _Veh.moto:
      // a motorcycle: thick wheels with rims, tank, engine, seat, fork, handlebar, headlight
      c(4.8, 17, 3.8);
      c(19.2, 17, 3.8);
      c(4.8, 17, 1.6);
      c(19.2, 17, 1.6);
      c(17.7, 9.6, .7);
      p
        ..addPath(_vehFill(v)!, Offset.zero)
        ..moveTo(4.6, 10.4)
        ..lineTo(10, 10.4)
        ..moveTo(4.8, 17)
        ..lineTo(9.6, 13.4)
        ..moveTo(5.6, 10.6)
        ..lineTo(9.6, 12.4)
        ..moveTo(15.4, 10.8)
        ..lineTo(16.4, 8.2)
        ..lineTo(19.2, 17)
        ..moveTo(16.4, 8.2)
        ..lineTo(16.6, 6.3)
        ..moveTo(15.2, 6.6)
        ..lineTo(17.8, 6)
        ..moveTo(6.4, 15.6)
        ..lineTo(9.6, 15.6);
  }
  return p;
}

/// The lightly filled parts: the moped's rear body, the motorcycle's tank and engine.
Path? _vehFill(_Veh v) {
  switch (v) {
    case _Veh.moped:
      return Path()
        ..moveTo(2.8, 15.8)
        ..cubicTo(2.8, 12.4, 5.4, 11, 9, 11.6)
        ..lineTo(10.4, 15.8)
        ..close();
    case _Veh.moto:
      return Path()
        ..moveTo(10, 10.8)
        ..quadraticBezierTo(10.6, 8.6, 13, 8.6)
        ..lineTo(14.2, 8.6)
        ..lineTo(15.4, 10.8)
        ..close()
        ..addRect(const Rect.fromLTRB(9.6, 11.8, 13.6, 15));
    default:
      return null;
  }
}

void _drawVeh(Canvas canvas, _Veh v, Offset center, double size, Color color, double stroke) {
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(size / 24);
  final fill = _vehFill(v);
  if (fill != null) canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .18));
  canvas.drawPath(
    _vehPath(v),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 24 / size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color,
  );
  canvas.restore();
}

class _VehPainter extends CustomPainter {
  final _Veh v;
  final Color color;
  final double stroke;
  _VehPainter(this.v, this.color, this.stroke);
  @override
  void paint(Canvas canvas, Size size) => _drawVeh(canvas, v, size.center(Offset.zero), size.width, color, stroke);
  @override
  bool shouldRepaint(covariant _VehPainter o) => false;
}

/// The city itself (streets, buildings with windows, park, lake). It does not move, so it is
/// drawn once into a picture and reused on every frame.
/// The city itself (streets, buildings with windows, park, lake). It does not move: the start
/// screen draws it once into an image ([drawCity]) and only moves that image.
class _CityPainter {
  final _Geo g;
  _CityPainter(this.g);

  /// Draws the city over [area] (screen units; larger than the screen so the tilted map never
  /// shows an edge). Far away it melts into white, like haze.
  void drawCity(Canvas canvas, Rect area) => _draw(canvas, area);

  void _draw(Canvas canvas, Rect area) {
    final s = g.s;
    Offset P(double x, double y, [double z = 0]) => g.p(x, y, z);

    // streets: light grey bands with a fine dashed white middle line
    final street = Paint()
      ..color = const Color(0xFFEEF2F4)
      ..strokeWidth = s * 1.15;
    final mid = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.1;
    for (var k = -36; k <= 45; k += 3) {
      final kk = k.toDouble();
      canvas.drawLine(P(kk, -45), P(kk, 60), street);
      canvas.drawLine(P(-45, kk), P(60, kk), street);
    }
    for (var k = -36; k <= 45; k += 3) {
      final kk = k.toDouble();
      for (double u = -45; u < 60; u += 0.7) {
        canvas.drawLine(P(kk, u), P(kk, u + .35), mid);
        canvas.drawLine(P(u, kk), P(u + .35, kk), mid);
      }
    }

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFC3CED6);
    void face(List<Offset> ps, Color c) {
      final path = Path()..addPolygon(ps, true);
      canvas.drawPath(path, Paint()..color = c);
      canvas.drawPath(path, edge);
    }

    final winFront = Paint()..color = const Color(0xFFDCE4EA);
    final winSide = Paint()..color = const Color(0xFFCCD6DE);

    // windows on a wall from a to b (along the ground) up to height z
    void windows(Offset Function(double u, double z) at, double len, double z, Paint paint) {
      const ww = .13, wh = .1, gapU = .26, gapZ = .24;
      for (double zz = .12; zz + wh < z - .06; zz += gapZ) {
        for (double u = .1; u + ww < len - .06; u += gapU) {
          canvas.drawPath(
              Path()..addPolygon([at(u, zz), at(u + ww, zz), at(u + ww, zz + wh), at(u, zz + wh)], true), paint);
        }
      }
    }

    var seed = 7;
    double rnd() => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    final blocks = <_Block>[];
    for (var i = -14; i < 16; i++) {
      for (var j = -14; j < 16; j++) {
        final x0 = i * 3 + .8, y0 = j * 3 + .8;
        if (i == 2 && j == 0) {
          blocks.add(_Block(x0, y0, 1.5, 1.5, 0, kind: 1));
          continue;
        }
        if (i == 0 && j == 2) {
          blocks.add(_Block(x0, y0, 1.5, 1.5, 0, kind: 2));
          continue;
        }
        blocks.add(_Block(x0 + .15, y0 + .15, 1.1, .6, .5 + rnd() * 1.4));
        blocks.add(_Block(x0 + .15, y0 + 1.0, .45, .4, .35 + rnd() * .6));
        blocks.add(_Block(x0 + .85, y0 + 1.0, .4, .35, .3 + rnd() * .5));
      }
    }
    blocks.sort((a, b) => (a.x0 + a.w + a.y0 + a.d).compareTo(b.x0 + b.w + b.y0 + b.d));

    final park = Paint()..color = const Color(0xFFD7EACB);
    final tree = Paint()..color = const Color(0xFFC4E0B0);
    final treeEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = const Color(0xFFA9CF90);
    for (final b in blocks) {
      final c = P(b.x0 + b.w / 2, b.y0 + b.d / 2);
      if (c.dx < area.left - 3 * s || c.dx > area.right + 3 * s || c.dy < area.top - 3 * s || c.dy > area.bottom + 4 * s) continue;
      if (b.kind == 1) {
        canvas.drawPath(
            Path()..addPolygon([P(b.x0, b.y0), P(b.x0 + 1.5, b.y0), P(b.x0 + 1.5, b.y0 + 1.5), P(b.x0, b.y0 + 1.5)], true),
            park);
        for (final o in const [Offset(.4, .4), Offset(1.1, .5), Offset(.7, 1.1), Offset(1.3, 1.25), Offset(.3, 1.3)]) {
          final q = P(b.x0 + o.dx, b.y0 + o.dy, .35);
          canvas.drawCircle(q, s * .27, tree);
          canvas.drawCircle(q, s * .27, treeEdge);
        }
        continue;
      }
      if (b.kind == 2) {
        canvas.drawPath(
            Path()..addPolygon([P(b.x0, b.y0), P(b.x0 + 1.5, b.y0), P(b.x0 + 1.5, b.y0 + 1.5), P(b.x0, b.y0 + 1.5)], true),
            Paint()..color = const Color(0xFFE3EEFB));
        continue;
      }
      final x0 = b.x0, y0 = b.y0, x1 = b.x0 + b.w, y1 = b.y0 + b.d, z = b.h;
      // front wall (facing the viewer, left), side wall (right), roof
      face([P(x0, y1), P(x1, y1), P(x1, y1, z), P(x0, y1, z)], const Color(0xFFF7F9FA));
      windows((u, zz) => P(x0 + u, y1, zz), b.w, z, winFront);
      face([P(x1, y0), P(x1, y1), P(x1, y1, z), P(x1, y0, z)], const Color(0xFFE6EBEF));
      windows((u, zz) => P(x1, y1 - u, zz), b.d, z, winSide);
      face([P(x0, y0, z), P(x1, y0, z), P(x1, y1, z), P(x0, y1, z)], Colors.white);
      // a small box on the roof of the taller ones
      if (z > 1.2) {
        final rx = x0 + b.w * .55, ry = y0 + b.d * .25, rz = z + .14;
        face([P(rx, ry + .2, z), P(rx + .25, ry + .2, z), P(rx + .25, ry + .2, rz), P(rx, ry + .2, rz)],
            const Color(0xFFF2F5F7));
        face([P(rx + .25, ry, z), P(rx + .25, ry + .2, z), P(rx + .25, ry + .2, rz), P(rx + .25, ry, rz)],
            const Color(0xFFE6EBEF));
        face([P(rx, ry, rz), P(rx + .25, ry, rz), P(rx + .25, ry + .2, rz), P(rx, ry + .2, rz)], Colors.white);
      }
    }

    // far away and at the sides the city melts into white (no hard edge anywhere)
    final w = g.w, h = g.h;
    canvas.drawRect(
        area,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, area.top), Offset(0, area.bottom), const [
            Colors.white,
            Colors.white,
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Colors.white,
          ], [
            0,
            ((-0.45 * h - area.top) / area.height).clamp(0.0, 1.0),
            ((0.02 * h - area.top) / area.height).clamp(0.0, 1.0),
            ((1.02 * h - area.top) / area.height).clamp(0.0, 1.0),
            1,
          ]));
    canvas.drawRect(
        area,
        Paint()
          ..shader = ui.Gradient.linear(Offset(area.left, 0), Offset(area.right, 0), const [
            Colors.white,
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Colors.white,
          ], [
            0,
            ((-0.1 * w - area.left) / area.width).clamp(0.0, 1.0),
            ((1.1 * w - area.left) / area.width).clamp(0.0, 1.0),
            1,
          ]));
  }

}

/// Your route on the ground: grey dots ahead, blue behind you; the green spot pulses at the end.
class _RoutePainter extends CustomPainter {
  final _Geo g;
  final double f, arrive;
  _RoutePainter(this.g, this.f, this.arrive);

  @override
  void paint(Canvas canvas, Size size) {
    final s = g.s;
    final pts = _route.map((p) => g.p(p.dx, p.dy)).toList();
    final full = Path()..addPolygon(pts, false);
    final dot = Paint()..color = const Color(0xFFB7C3CB);
    for (final m in full.computeMetrics()) {
      for (double d = 0; d < m.length; d += 6) {
        canvas.drawCircle(m.getTangentForOffset(d)!.position, 0.8, dot);
      }
      if (f > 0) {
        final part = m.extractPath(0, m.length * f);
        canvas.drawPath(
            part,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.blue.withValues(alpha: .18));
        canvas.drawPath(
            part,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.blue);
      }
    }
    if (arrive > 0) {
      final c = g.p(_route.last.dx, _route.last.dy);
      final pulse = math.sin(arrive * math.pi);
      canvas.drawOval(Rect.fromCenter(center: c, width: s * 3.2, height: s * 1.6),
          Paint()..color = AppColors.green.withValues(alpha: .14 * arrive));
      canvas.drawOval(
          Rect.fromCenter(center: c, width: s * (3.4 + 2.4 * arrive), height: s * (1.7 + 1.2 * arrive)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = AppColors.green.withValues(alpha: .4 * pulse));
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter o) => o.f != f || o.arrive != arrive;
}

/// The riders (small white bubbles with a fine vehicle icon) and you (the blue one).
class _RiderPainter extends CustomPainter {
  final double t, show;
  final Offset me;
  final List<(_Veh, Offset)> others;
  _RiderPainter({required this.t, required this.show, required this.me, required this.others});

  @override
  void paint(Canvas canvas, Size size) {
    if (show <= 0) return;
    for (final (v, at) in others) {
      _bubble(canvas, at, v, false);
    }
    _bubble(canvas, me, _Veh.bike, true);
  }

  void _bubble(Canvas canvas, Offset at, _Veh v, bool mine) {
    final r = (mine ? 13.0 : 10.5) * show;
    final c = mine ? AppColors.blue : const Color(0xFF8C9AA3);
    final center = at - Offset(0, r + 3);
    if (mine) canvas.drawCircle(center, r + 6, Paint()..color = AppColors.blue.withValues(alpha: .12));
    canvas.drawShadow(Path()..addOval(Rect.fromCircle(center: center, radius: r)), Colors.black, 2, false);
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mine ? 1.6 : 1
          ..color = c);
    canvas.drawCircle(at, 1.6, Paint()..color = c);
    _drawVeh(canvas, v, center, r * 1.5, mine ? AppColors.blue : AppColors.soft, mine ? 1.5 : 1.2);
  }

  @override
  bool shouldRepaint(covariant _RiderPainter o) => o.t != t;
}

class _Block {
  final double x0, y0, w, d, h;
  final int kind; // 0 building, 1 park, 2 lake
  const _Block(this.x0, this.y0, this.w, this.d, this.h, {this.kind = 0});
}
