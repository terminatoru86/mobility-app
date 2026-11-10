// A picture of the start screen, made on GitHub (workflow "Preview pictures"), to check the
// design without a phone. Not part of the normal tests.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobility/theme.dart';
import 'package:mobility/widgets/city_splash.dart';

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
    await t.pump(const Duration(milliseconds: 330)); // the first dot, the m is drawing
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start1.png'));
    await t.pump(const Duration(milliseconds: 470)); // all dots, the m is done
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start2.png'));
    await t.pump(const Duration(milliseconds: 700)); // the city comes, the logo rises
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start3.png'));
    await t.pump(const Duration(milliseconds: 700));
    await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('out/start4.png'));
    await t.pump(const Duration(milliseconds: 1000)); // the end
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
}
