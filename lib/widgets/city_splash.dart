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
/// straight on the working map). One smooth take, like a short film, all of it played by the
/// app on one clock (so nothing jumps):
///
/// 1. the plain grey of Android's own start (nothing on it, so nothing can jump); the first dot
///    lights up, then the "m" draws itself over the dots as they light: red, yellow, green
/// 2. from the second dot on the grey slowly opens up and the city with our pins comes through
/// 3. after the last dot the logo rises gently and MOBIlity appears under it
/// 4. "Get started" and our four vehicles come up at the bottom; tapping it opens the map
///    (main.dart), then the sign-in pop-up.
///
/// The heavy work (the map) starts only when the film is over ([onShown]), so the film never
/// stutters.
class CitySplash extends StatefulWidget {
  /// "Get started" was tapped.
  final VoidCallback? onStart;

  /// The film is over (the button is on screen).
  final VoidCallback? onShown;
  const CitySplash({super.key, this.onStart, this.onShown});
  @override
  State<CitySplash> createState() => _StartState();
}

/// [t] in milliseconds on the film's clock, 0..1 between [a] and [b].
double _ms(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _StartState extends State<CitySplash> with SingleTickerProviderStateMixin {
  static const _len = 3300.0; // the film, in milliseconds
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3300));

  @override
  void initState() {
    super.initState();
    _a.addStatusListener((st) {
      if (st == AnimationStatus.completed) widget.onShown?.call();
    });
    // the first frame is the plain grey (the same as Android's own start); the film plays at once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _a.forward();
    });
    _cityReady.addListener(_cityCame);
  }

  void _cityCame() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cityReady.removeListener(_cityCame);
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final img = _cityImage;
        // the finished background, painted from the first frame on (under the grey), so nothing
        // has to be prepared in the middle of the film
        final city = RepaintBoundary(
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: AppColors.paper),
            if (img != null)
              RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium)
            else if (_cityReady.value)
              const SplashArt(showTitle: false), // the file could not be read: draw it
            // a touch of white over the city
            const ColoredBox(color: Color(0x2EFFFFFF)),
            // soft light behind the logo and at the bottom, so they read well on the city
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.48),
                  radius: 0.55,
                  colors: [Color(0xF2F5F7F7), Color(0xB3F5F7F7), Color(0x00F5F7F7)],
                  stops: [0, .5, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00F5F7F7), Color(0x00F5F7F7), Color(0xE6F5F7F7)],
                  stops: [0, .62, .86],
                ),
              ),
            ),
          ]),
        );
        return AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final t = _a.value * _len;
            // a short breath on the grey, then the first dot; the "m" draws itself unhurriedly
            final d1 = Curves.easeOut.transform(_ms(t, 150, 480)); // red dot
            final d2 = Curves.easeOut.transform(_ms(t, 500, 830)); // yellow dot
            final d3 = Curves.easeOut.transform(_ms(t, 820, 1150)); // green dot
            final draw = Curves.easeInOutSine.transform(_ms(t, 220, 1200)); // the "m" draws itself
            final bg = Curves.easeInOutSine.transform(_ms(t, 600, 2650)); // the grey opens, the city comes
            final sp = Curves.easeInOutSine.transform(_ms(t, 1000, 2600)); // the logo rises
            final name = Curves.easeOut.transform(_ms(t, 1600, 2550)); // MOBIlity under the logo
            final btn = Curves.easeOutCubic.transform(_ms(t, 2200, 3300)); // Get started and the vehicles
            final logo = ui.lerpDouble(kSplashLogo, 116, sp)!;
            final logoY = ui.lerpDouble(h / 2, h * 0.25, sp)!; // centre of the logo
            return Stack(fit: StackFit.expand, children: [
              city,
              // the grey of the first moment (Android's own start is the same) lies over it and
              // slowly clears
              IgnorePointer(child: ColoredBox(color: kStartGrey.withValues(alpha: 1 - bg))),
              // the logo
              Positioned(
                left: (w - logo) / 2,
                top: logoY - logo / 2,
                width: logo,
                height: logo,
                child: CustomPaint(painter: LogoPainter(red: d1, yellow: d2, green: d3, draw: draw)),
              ),
              // MOBIlity under it
              Positioned(
                left: 0,
                right: 0,
                top: logoY + logo / 2 + 4,
                child: Opacity(
                  opacity: name,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - name)),
                    child: const Text('MOBIlity',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: 0.5)),
                  ),
                ),
              ),
              // Get started
              Positioned(
                left: 24,
                right: 24,
                bottom: pad.bottom + 74,
                child: IgnorePointer(
                  ignoring: btn < 0.5,
                  child: Opacity(
                    opacity: btn,
                    child: Transform.translate(
                      offset: Offset(0, 24 * (1 - btn)),
                      child: SizedBox(
                        height: 54,
                        child: TextButton(
                          onPressed: widget.onStart,
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                          ),
                          child: const Text('Get started'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // our four vehicles at the bottom, with the button
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 18 - 16 * (1 - btn),
                child: Opacity(
                  opacity: btn,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final v in _Veh.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CustomPaint(size: const Size(32, 32), painter: _VehPainter(v, AppColors.soft, 1.5)),
                      ),
                  ]),
                ),
              ),
            ]);
          },
        );
      });
  }
}

/// Our "m" with the three status dots, drawn directly (it is there in the very first frame).
class LogoPainter extends CustomPainter {
  /// How much each dot is lit, 0..1.
  final double red, yellow, green;

  /// Loading: a route through the dots that fills from the red dot to the green one, left to
  /// right like a loading bar, 0..1 (the dots light as it reaches them). Null: no route.
  final double? route;

  /// How much of the "m" is drawn, 0..1 (it draws itself from left to right).
  final double draw;
  const LogoPainter({this.red = 1, this.yellow = 1, this.green = 1, this.route, this.draw = 1});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64);
    final m = Path()
      ..moveTo(14, 44)
      ..lineTo(14, 28)
      ..arcToPoint(const Offset(32, 28), radius: const Radius.circular(9))
      ..lineTo(32, 44)
      ..moveTo(32, 28)
      ..arcToPoint(const Offset(50, 28), radius: const Radius.circular(9))
      ..lineTo(50, 44);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF24333C);
    if (draw >= 1) {
      canvas.drawPath(m, ink);
    } else if (draw > 0) {
      final parts = m.computeMetrics().toList();
      final total = parts.fold<double>(0, (a, e) => a + e.length);
      var left = total * draw;
      for (final e in parts) {
        if (left <= 0) break;
        canvas.drawPath(e.extractPath(0, left.clamp(0.0, e.length)), ink);
        left -= e.length;
      }
    }
    final r = route;
    if (r != null) {
      const off = Color(0xFFC3CCD1);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      // the road still to do, then the part done (green, yellow, red as it goes)
      canvas.drawLine(const Offset(14, 54), const Offset(50, 54), line..color = off);
      if (r > 0) {
        canvas.drawLine(
            const Offset(14, 54),
            Offset(14 + 36 * r, 54),
            line
              ..shader = const LinearGradient(colors: [Color(0xFFE0484D), Color(0xFFE9A800), Color(0xFF5D9A30)])
                  .createShader(const Rect.fromLTRB(14, 50, 50, 58)));
      }
      for (final x in const [14.0, 32.0, 50.0]) {
        canvas.drawCircle(Offset(x, 54), 4.6, Paint()..color = off);
      }
    }
    canvas.drawCircle(const Offset(14, 54), 4.6, Paint()..color = const Color(0xFFE0484D).withValues(alpha: red));
    canvas.drawCircle(const Offset(32, 54), 4.6, Paint()..color = const Color(0xFFE9A800).withValues(alpha: yellow));
    canvas.drawCircle(const Offset(50, 54), 4.6, Paint()..color = const Color(0xFF5D9A30).withValues(alpha: green));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoPainter o) => o.red != red || o.yellow != yellow || o.green != green || o.route != route || o.draw != draw;
}

/// The loading screen for a signed-in rider, on the plain grey of Android's own start (nothing
/// there, so nothing can jump): our "m" stands still, and only the route through the three dots
/// moves, from left to right like a game's loading bar: red, yellow, and green when the map is ready.
/// Then the screen fades out over the working map. Quick and smooth.
class LoadingLogo extends StatefulWidget {
  /// Loads the app; completes when the map is on screen (under this screen).
  final Future<void> Function() prepare;

  /// The screen has faded out.
  final VoidCallback onDone;
  const LoadingLogo({super.key, required this.prepare, required this.onDone});
  @override
  State<LoadingLogo> createState() => _LoadingLogoState();
}

class _LoadingLogoState extends State<LoadingLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);
  bool _out = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    // red, then on to yellow and a little further while the app loads...
    await Future.wait([
      _a.animateTo(0.72, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic).orCancel.catchError((_) {}),
      widget.prepare(),
    ]);
    if (!mounted) return;
    // ...the map is ready: the route reaches green, and the screen clears
    await _a.animateTo(1, duration: const Duration(milliseconds: 220), curve: Curves.easeInOut).orCancel.catchError((_) {});
    if (!mounted) return;
    setState(() => _out = true);
    await Future.delayed(const Duration(milliseconds: 240));
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _out,
      child: AnimatedOpacity(
        opacity: _out ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: ColoredBox(
          color: kStartGrey,
          child: Center(
            child: SizedBox(
              width: kSplashLogo,
              height: kSplashLogo,
              child: AnimatedBuilder(
                animation: _a,
                builder: (context, _) {
                  final p = _a.value;
                  return CustomPaint(
                    painter: LogoPainter(
                      route: p,
                      red: Curves.easeOut.transform(_ms(p, 0, 0.12)),
                      yellow: Curves.easeOut.transform(_ms(p, 0.42, 0.56)),
                      green: Curves.easeOut.transform(_ms(p, 0.9, 1)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The city behind the start screen as a file (made from [SplashArt] on GitHub, see preview/).
const String kCityPicture = 'assets/splash/city.jpg';
ui.Image? _cityImage;
final ValueNotifier<bool> _cityReady = ValueNotifier(false);

/// Reads the city picture in the background (the logo moves meanwhile; the city comes in later).
Future<void> loadStartPicture() async {
  try {
    final data = await rootBundle.load(kCityPicture);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    _cityImage = (await codec.getNextFrame()).image;
  } catch (_) {}
  _cityReady.value = true;
}

/// The start picture, drawn: the city, pins, riders, route, the logo and MOBIlity, the line and
/// the vehicles. Used to make [kCityPicture] (and if that file is missing).
class SplashArt extends StatefulWidget {
  /// With the logo, MOBIlity, the line and the vehicles (false: only the city).
  final bool showTitle;
  const SplashArt({super.key, this.showTitle = true});
  @override
  State<SplashArt> createState() => _CitySplashState();
}

/// The line on the start screen, above the vehicles.
const String kSplashLine = 'Ride in. Park easy.';

/// The logo's size on the start screen (Android's own start draws it the same size, in the middle).
const double kSplashLogo = 170;

/// The darker grey of the very first moment (Android's own start uses the same).
const Color kStartGrey = Color(0xFFE8EDEF);


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
  // and more between them, so the whole picture is alive
  (4.5, 0, _place('v', PlaceType.rack, Status.free, '4')),
  (3, 4.5, _place('w', PlaceType.rack, Status.almost, '1')),
  (7.5, 3, _place('x', PlaceType.parkOutdoor, Status.free, '6')),
  (0, 7.5, _place('y', PlaceType.rack, Status.free, '3')),
  (7.5, 6, _place('z', PlaceType.charging, Status.free, '2')),
  (1.5, 9, _place('a2', PlaceType.rack, Status.full, '0')),
  (12, 7.5, _place('b2', PlaceType.rack, Status.free, '5')),
  (6, 10.5, _place('c2', PlaceType.parkCovered, Status.almost, '1')),
  (9, 10.5, _place('d2', PlaceType.rack, Status.free, '2')),
  (0, 4.5, _place('e2', PlaceType.parkOutdoor, Status.free, '7')),
  (12, 4.5, _place('f2', PlaceType.rack, Status.almost, '1')),
  (12, 10.5, _place('g2', PlaceType.rack, Status.free, '3')),
];
const _arriveAt = 2; // index of the green pin you ride to

/// Where pin [i] stands: on its street, slid a little along it (each one differently), so the pins
/// do not line up in rows.
Offset _pinAt(int i) {
  final x = _pins[i].$1, y = _pins[i].$2;
  if (i == _arriveAt) return Offset(x, y); // the end of your route stays put
  final j = ((i * 37 + 11) % 17) / 17 * 1.5 - 0.75;
  return x % 3 == 0 ? Offset(x, y + j) : Offset(x + j, y);
}

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
          for (var i = 0; i < _pins.length; i++) (screen(_pinAt(i).dx, _pinAt(i).dy), i),
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
                      final depth = (0.56 + 0.36 * (pt.dy / h)).clamp(0.55, 0.95);
                      const dim = 1.0;
                      final full = place.status == Status.full ? 0.85 : 1.0;
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
          if (widget.showTitle) _Title(h: h),
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
      ..color = const Color(0xFFE3E9ED)
      ..strokeWidth = s * 1.0;
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
    final pads = <Offset>[]; // the pavement under each block of buildings
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
        pads.add(Offset(x0, y0));
        // every block of the city is built differently: a tower, slabs, houses, a courtyard...
        final kind = (rnd() * 6).floor();
        switch (kind) {
          case 0: // a tall tower with a low annex
            blocks.add(_Block(x0 + .1, y0 + .1, .8, .8, 1.9 + rnd() * 1.1));
            blocks.add(_Block(x0 + 1.0, y0 + .75, .45, .6, .35 + rnd() * .4));
          case 1: // two long slabs
            blocks.add(_Block(x0 + .05, y0 + .05, 1.35, .5, .9 + rnd() * .8));
            blocks.add(_Block(x0 + .05, y0 + .85, 1.35, .5, .5 + rnd() * .5));
          case 2: // small houses
            blocks.add(_Block(x0 + .05, y0 + .1, .55, .5, .35 + rnd() * .35));
            blocks.add(_Block(x0 + .8, y0 + .05, .55, .55, .4 + rnd() * .4));
            blocks.add(_Block(x0 + .1, y0 + .85, .5, .5, .3 + rnd() * .35));
            blocks.add(_Block(x0 + .8, y0 + .85, .6, .5, .45 + rnd() * .5));
          case 3: // a wide block with a tower at its corner
            blocks.add(_Block(x0 + .05, y0 + .05, 1.35, .7, .8 + rnd() * .6));
            blocks.add(_Block(x0 + .75, y0 + .85, .6, .55, 1.6 + rnd() * .9));
          case 4: // one big wide building
            blocks.add(_Block(x0 + .05, y0 + .15, 1.4, 1.1, .6 + rnd() * .7));
          default: // a slim high-rise and a mid one
            blocks.add(_Block(x0 + .1, y0 + .1, .55, .55, 2.2 + rnd() * 1.0));
            blocks.add(_Block(x0 + .8, y0 + .15, .6, 1.1, .9 + rnd() * .7));
        }
      }
    }
    blocks.sort((a, b) => (a.x0 + a.w + a.y0 + a.d).compareTo(b.x0 + b.w + b.y0 + b.d));

    // pavements: a white pad with a fine edge under every block, so the streets read as streets
    final padEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = const Color(0xFFD3DBE1);
    for (final o in pads) {
      final c = P(o.dx + .75, o.dy + .75);
      if (c.dx < area.left - 3 * s || c.dx > area.right + 3 * s || c.dy < area.top - 3 * s || c.dy > area.bottom + 4 * s) continue;
      final pad = Path()
        ..addPolygon([P(o.dx - .12, o.dy - .12), P(o.dx + 1.62, o.dy - .12), P(o.dx + 1.62, o.dy + 1.62), P(o.dx - .12, o.dy + 1.62)], true);
      canvas.drawPath(pad, Paint()..color = const Color(0xFFFBFCFC));
      canvas.drawPath(pad, padEdge);
    }

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
