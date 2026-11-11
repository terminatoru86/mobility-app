// A picture of the start screen, made on GitHub (workflow "Preview pictures"), to check the
// design without a phone. Not part of the normal tests.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobility/theme.dart';
import 'package:mobility/widgets/city_splash.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobility/data/places.dart';
import 'package:mobility/widgets/place_sheet.dart';
import 'package:mobility/widgets/share_pin.dart';
import 'package:mobility/widgets/share_sheet.dart';
import 'package:mobility/widgets/signup.dart';

Future<void> _fonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final l = FontLoader('Roboto');
  for (final f in dir.listSync().whereType<File>()) {
    final n = f.uri.pathSegments.last;
    if (n.startsWith('Roboto-') && n.endsWith('.ttf')) {
      final b = f.readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
  }
  await l.load();
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final b = icons.readAsBytesSync();
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(b.buffer)))).load();
  }
}

Widget _phone(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
      home: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Material(
            child: Transform.scale(
              scale: _dpr,
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 1080 / _dpr,
                maxWidth: 1080 / _dpr,
                minHeight: 2400 / _dpr,
                maxHeight: 2400 / _dpr,
                child: MediaQuery(
                    data: const MediaQueryData(size: Size(1080 / _dpr, 2400 / _dpr), padding: EdgeInsets.only(top: 24, bottom: 16)),
                    child: child),
              ),
            ),
          ),
        ),
      ),
    );

// drawn at the phone's size in points (1080 x 2400 px at 2.625), saved at full pixels
const _dpr = 2.625;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  testWidgets('city picture (behind the start screen)', (t) async {
    await t.runAsync(_fonts);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(_phone(const SplashArt(showTitle: false)));
    await _settle(t);
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/city.png'));
  });

  testWidgets('start screen, the film in five moments', (t) async {
    await t.runAsync(_fonts);
    await t.runAsync(loadStartPicture);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(_phone(const CitySplash()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    await t.pump(const Duration(milliseconds: 620)); // the first dots, the m is drawing
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start1.png'));
    await t.pump(const Duration(milliseconds: 600)); // all dots, the m is done
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start2.png'));
    await t.pump(const Duration(milliseconds: 700)); // the city comes, the logo rises
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start3.png'));
    await t.pump(const Duration(milliseconds: 700));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start4.png'));
    await t.pump(const Duration(milliseconds: 1100)); // the end
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start5.png'));
  });

  testWidgets('loading logo (signed in)', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    final never = Completer<void>();
    await t.pumpWidget(_phone(LoadingLogo(prepare: () => never.future, onDone: () {})));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    await t.pump(const Duration(milliseconds: 160));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/loading1.png'));
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/loading2.png'));
  });

  testWidgets('sign-in sheet', (t) async {
    await t.runAsync(_fonts);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(_phone(const ColoredBox(
        color: Color(0xFFDDE5E9), child: Align(alignment: Alignment.bottomCenter, child: SignInCard()))));
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/signin.png'));
  });

  Place share(String name, ShareInfo i, {Status st = Status.free}) => Place(
      id: name,
      type: PlaceType.sharing,
      address: name,
      pos: const LatLng(41.885, -87.63),
      status: st,
      distance: '300 m',
      etaMin: const {},
      operatorName: 'Divvy',
      share: i);

  testWidgets('ride share: pins and the two sheets', (t) async {
    await t.runAsync(_fonts);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    final hub = share('Clark St & Lake St', const ShareInfo(ebikes: 4, classic: 7, scooters: 2, docks: 6));
    final bike = share('Divvy e-bike · No. 4471', const ShareInfo(street: true, ebikes: 1, battery: 82, rangeM: 35000, code: '4471'));
    final pins = [
      hub,
      share('b', const ShareInfo(ebikes: 3, classic: 5, docks: 2)),
      share('c', const ShareInfo(classic: 2, docks: 2), st: Status.almost),
      share('d', const ShareInfo(docks: 15), st: Status.full),
      bike,
      share('f', const ShareInfo(street: true, scooters: 1, battery: 35)),
      share('g', const ShareInfo(street: true, scooters: 1, battery: 9)),
    ];
    final sc = ScrollController();
    await t.pumpWidget(_phone(ColoredBox(
      color: const Color(0xFFDDE5E9),
      child: Column(children: [
        const SizedBox(height: 60),
        Wrap(spacing: 14, runSpacing: 16, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.end, children: [
          for (final p in pins) SharePin(place: p),
          SharePin(place: hub, open: true),
          SharePin(place: hub, open: true, selected: true),
          SharePin(place: bike, selected: true),
          const WalkBubble(4),
        ]),
        const Spacer(),
        SizedBox(height: 200, child: PlaceSheet(place: bike, scroll: sc)),
        const SizedBox(height: 16),
        SizedBox(height: 270, child: PlaceSheet(place: hub, scroll: ScrollController())),
      ]),
    )));
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/share.png'));
  });

  testWidgets('place sheet above the main menu', (t) async {
    await t.runAsync(_fonts);
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    final hub = share('Clark St & Lake St', const ShareInfo(ebikes: 4, classic: 1, scooters: 0, docks: 6));
    final key = GlobalKey<ScaffoldState>();
    await t.pumpWidget(_phone(Scaffold(
      key: key,
      backgroundColor: const Color(0xFFDDE5E9),
      body: const Center(child: Text('map')),
      bottomNavigationBar: NavigationBar(destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
        NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Routes'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
      ]),
    )));
    showPlaceSheet(key.currentContext!, hub, host: key.currentState);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/share_host.png'));
    closePlaceSheet();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PlaceSheet), findsNothing);
  });
}
