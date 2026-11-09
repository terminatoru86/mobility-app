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
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
      home: const DefaultTextStyle(style: TextStyle(fontFamily: 'Roboto'), child: Material(child: CitySplash())),
    ));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(CitySplash), matchesGoldenFile('out/splash.png'));
  });
}
