// A picture of the start screen, made on GitHub (workflow "Preview pictures"), to check the
// design without a phone. Not part of the normal tests.
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

void main() {
  testWidgets('start picture', (t) async {
    await t.runAsync(_fonts);
    // drawn at the phone's size in points (1080 x 2400 px at 2.625), saved at full pixels
    const dpr = 2.625;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
      home: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: RepaintBoundary(
          key: const ValueKey('start'),
          child: Material(
          child: Transform.scale(
            scale: dpr,
            alignment: Alignment.topLeft,
            child: const OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 1080 / dpr,
              maxWidth: 1080 / dpr,
              minHeight: 2400 / dpr,
              maxHeight: 2400 / dpr,
              child: MediaQuery(data: MediaQueryData(size: Size(1080 / dpr, 2400 / dpr), padding: EdgeInsets.only(bottom: 16)), child: SplashArt()),
            ),
          ),
          ),
        ),
      ),
    ));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byKey(const ValueKey('start')), matchesGoldenFile('out/start.png'));
  });
}
