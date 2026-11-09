import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../data/app_state.dart';
import '../data/places.dart';
import '../theme.dart';
import 'pin.dart';
import 'signup.dart';

/// The start screen, only for people without an account (once signed in, the app opens
/// straight on the working map). About 3.5 s, one smooth take:
///
/// 1. the city is there at once, in 3D, under a white haze that lifts from the middle out
///    (soft edges at the top and bottom, no hard border anywhere)
/// 2. our real map pins come in, and other riders on bike, scooter, moped, motorcycle
/// 3. your blue route is drawn; with it the "m" logo and MOBI appear in the middle
/// 4. you arrive: the green pin pulses
/// 5. the sign-in panel slides up over the map (Apple, Google, or continue as guest).
class CitySplash extends StatefulWidget {
  /// The app state, ready when Firebase and the saved data have loaded (while the city plays).
  final Future<AppState> state;
  /// Called when the city has played: the map can be built behind it.
  final VoidCallback? onEnding;
  const CitySplash({super.key, required this.state, this.onEnding});
  @override
  State<CitySplash> createState() => _CitySplashState();
}

/// The line on the last screen, above the vehicles.
const String kSplashLine = 'Ride in. Park easy.';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

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

class _CitySplashState extends State<CitySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) _askSignIn();
    });

  @override
  void initState() {
    super.initState();
    // start moving with the first frame on screen (not while the app is still starting)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _a.forward();
    });
  }
  bool _signIn = false; // our sign-in pop-up is open
  bool _fading = false;
  bool _gone = false;

  // The city is drawn once. First as a picture (on screen at once), then turned into an image
  // in the background; from then on every frame only moves the image (smooth).
  ui.Picture? _pic;
  ui.Image? _img;
  Size? _forSize;

  @override
  void dispose() {
    _a.dispose();
    _pic?.dispose();
    _img?.dispose();
    super.dispose();
  }

  /// The drawn area: bigger than the screen, so the tilted map never shows an edge.
  static Rect _area(double w, double h) => Rect.fromLTRB(-0.6 * w, -1.5 * h, 1.6 * w, 1.3 * h);

  void _draw(_Geo g, Size size, double dpr) {
    _pic?.dispose();
    _img?.dispose();
    _img = null;
    final area = _area(size.width, size.height);
    final rec = ui.PictureRecorder();
    _CityPainter(g).drawCity(Canvas(rec)..translate(-area.left, -area.top), area);
    _pic = rec.endRecording();
    _forSize = size;
    // the image, a moment later
    final r = math.min(dpr, 1.3);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rec2 = ui.PictureRecorder();
      _CityPainter(g).drawCity(
          Canvas(rec2)
            ..scale(r)
            ..translate(-area.left, -area.top),
          area);
      final pic2 = rec2.endRecording();
      final img = await pic2.toImage((area.width * r).round(), (area.height * r).round());
      pic2.dispose();
      if (!mounted || _forSize != size) {
        img.dispose();
        return;
      }
      setState(() => _img = img);
    });
  }

  /// The start screen ends: our sign-in pop-up over the map.
  Future<void> _askSignIn() async {
    if (_signIn) return;
    final st = await widget.state; // normally ready long before the city has played
    if (!mounted) return;
    widget.onEnding?.call();
    setState(() => _signIn = true);
    final ok = await showSignIn(context, st);
    if (!mounted) return;
    setState(() => _fading = true);
    // signed in: which vehicle do you ride? (cannot be skipped)
    if (ok) await showVehicleStep(context, st);
  }

  /// The 3D camera: perspective and tilt over the flat city, gliding down slowly.
  static Matrix4 _camera(double w, double h, double t) {
    final e = Curves.easeInOutSine.transform(t);
    final tilt = 0.74 - 0.16 * e;
    final zoom = 1.66 - 0.26 * e;
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
    if (_gone) return const SizedBox.shrink();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return IgnorePointer(
      ignoring: _fading,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOut,
        onEnd: () {
          if (_fading && mounted) setState(() => _gone = true);
        },
        child: ColoredBox(
          color: Colors.white,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final size = Size(w, h);
            final g = _Geo(w, h);
            if (_pic == null || _forSize != size) _draw(g, size, dpr);
            final area = _area(w, h);
            return AnimatedBuilder(
              animation: _a,
              builder: (context, _) {
                final t = _a.value;
                final m = _camera(w, h, t);
                Offset screen(double x, double y) => MatrixUtils.transformPoint(m, g.p(x, y));
                // timeline (0..1 of 3.5 s)
                final clear = Curves.easeOutCubic.transform(_seg(t, 0.0, 0.28)); // a thin haze lifts
                final pinsIn = _seg(t, 0.10, 0.40);
                final routeF = Curves.easeInOutSine.transform(_seg(t, 0.24, 0.80));
                final arrive = _seg(t, 0.78, 0.96);
                final ride = Curves.easeInOutSine.transform(_seg(t, 0.0, 1.0));

                final pins = <(Offset, int)>[
                  for (var i = 0; i < _pins.length; i++) (screen(_pins[i].$1, _pins[i].$2), i),
                ]..sort((a, b) => a.$1.dy.compareTo(b.$1.dy));

                return Stack(fit: StackFit.expand, children: [
                  Transform(
                    transform: m,
                    filterQuality: FilterQuality.medium,
                    child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                      Positioned(
                        left: area.left,
                        top: area.top,
                        width: area.width,
                        height: area.height,
                        child: _img != null
                            ? RawImage(image: _img, fit: BoxFit.fill, filterQuality: FilterQuality.medium)
                            : CustomPaint(painter: _PicturePainter(_pic!)),
                      ),
                      CustomPaint(painter: _RoutePainter(g, routeF, arrive)),
                    ]),
                  ),
                  // pins: the same pins as on the app map, coming in gently one after another
                  for (final (pt, i) in pins)
                    Builder(builder: (_) {
                      final start = i / _pins.length * 0.55;
                      final k = Curves.easeOutCubic.transform(_seg(pinsIn, start, start + 0.45));
                      if (k <= 0) return const SizedBox.shrink();
                      final place = _pins[i].$3;
                      final depth = (0.48 + 0.34 * (pt.dy / h)).clamp(0.45, 0.85);
                      final dim = i != _arriveAt && arrive > 0 ? 1 - 0.5 * arrive : 1.0;
                      final full = place.status == Status.full ? 1 - 0.45 * _seg(routeF, .2, .5) : 1.0;
                      final pulse = i == _arriveAt ? 1 + 0.16 * math.sin(arrive * math.pi) : 1.0;
                      return Positioned(
                        left: pt.dx - PlacePin.width / 2,
                        top: pt.dy - PlacePin.height,
                        child: Opacity(
                          opacity: (k * dim * full).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: depth * (0.7 + 0.3 * k) * pulse,
                            alignment: Alignment.bottomCenter,
                            child: PlacePin(place: place, animate: false, detail: PinDetail.full, showRating: false),
                          ),
                        ),
                      );
                    }),
                  // the riders (moving the whole time) and you, on your route
                  CustomPaint(
                    painter: _RiderPainter(
                      t: t,
                      show: Curves.easeOut.transform(_seg(t, 0.12, 0.30)),
                      me: _routePoint(routeF, screen),
                      others: [
                        for (final (v, a, b) in _riders)
                          (v, () {
                            final q = Offset.lerp(a, b, ride)!;
                            return screen(q.dx, q.dy);
                          }()),
                      ],
                    ),
                  ),
                  // the map melts into white all round, in a soft oval (no straight edge anywhere)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.08),
                          radius: 0.62,
                          transform: _Oval(h / w),
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x33FFFFFF),
                            Color(0x99FFFFFF),
                            Color(0xE6FFFFFF),
                            Colors.white,
                          ],
                          stops: const [0, .55, .70, .84, .94, 1],
                        ),
                      ),
                    ),
                  ),
                  // a thin white haze that lifts from the middle out
                  if (clear < 1)
                    IgnorePointer(
                      child: Opacity(
                        opacity: 0.85 * (1 - clear),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.05),
                              radius: 0.25 + 0.9 * clear,
                              transform: _Oval(h / w),
                              colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Colors.white],
                              stops: const [0, .6, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  _Title(t: t, signIn: _signIn),
                ]);
              },
            );
          }),
        ),
      ),
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

/// Stretches a round gradient into an oval that fits the tall screen.
class _Oval extends GradientTransform {
  final double k; // height / width
  const _Oval(this.k);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final c = bounds.center;
    return Matrix4.identity()
      ..translate(c.dx, c.dy)
      ..scale(1.0, k * bounds.width / bounds.shortestSide)
      ..translate(-c.dx, -c.dy);
  }
}

class _PicturePainter extends CustomPainter {
  final ui.Picture pic;
  _PicturePainter(this.pic);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPicture(pic);
  @override
  bool shouldRepaint(covariant _PicturePainter o) => o.pic != pic;
}

/// On top of the map: a soft white glow, in the middle the "m" logo and MOBI (they come in
/// with the route); bottom-right a small "Powered by MOBIlity"; at the bottom one short line
/// and our four vehicles (they make room when the sign-in panel comes up).
class _Title extends StatelessWidget {
  final double t;
  final bool signIn;
  const _Title({required this.t, required this.signIn});

  static const _word = 'MOBI';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final glow = Curves.easeInOutSine.transform(_seg(t, 0.22, 0.45));
    final logo = Curves.easeOutCubic.transform(_seg(t, 0.24, 0.40));
    final foot = Curves.easeOutCubic.transform(_seg(t, 0.55, 0.75));
    final by = Curves.easeOut.transform(_seg(t, 0.40, 0.60));
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        Opacity(
          opacity: glow,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.28),
                radius: 0.62,
                colors: [Color(0xE6FFFFFF), Color(0xA6FFFFFF), Color(0x00FFFFFF)],
                stops: [0, .45, 1],
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: logo,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - logo)),
                child: SvgPicture.asset('assets/brand/logo_m.svg', width: 92, height: 92),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _word.length; i++)
                Builder(builder: (_) {
                  final start = 0.28 + i * 0.05;
                  final k = Curves.easeOutCubic.transform(_seg(t, start, start + 0.10));
                  return Opacity(
                    opacity: k,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - k)),
                      child: Text(_word[i],
                          style: const TextStyle(
                              fontSize: 42, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: 1)),
                    ),
                  );
                }),
            ]),
          ]),
        ),
        // the line and the vehicles; they step aside when the sign-in panel comes up
        AnimatedOpacity(
          opacity: signIn ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Stack(fit: StackFit.expand, children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 46 + bottom,
              child: Opacity(
                opacity: foot,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - foot)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(kSplashLine,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.soft, letterSpacing: 0.2)),
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
              ),
            ),
            Positioned(
              right: 16,
              bottom: 14 + bottom,
              child: Opacity(
                opacity: by * 0.9,
                child: const Text('Powered by MOBIlity',
                    style: TextStyle(fontSize: 10, color: Color(0xFF97A3A9), letterSpacing: 0.2)),
              ),
            ),
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
