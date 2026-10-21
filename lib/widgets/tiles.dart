import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/store.dart';

/// Calm, light-grey version of the OpenStreetMap map, so our coloured pins
/// and the blue routes stand out. (Before launch: a provider with our own key.)
bool get _night {
  final t = Store.i.theme;
  if (t == ThemeMode.dark) return true;
  if (t == ThemeMode.system) {
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }
  return false;
}

// Night: dark grey streets, light labels.
const _nightMatrix = <double>[
  -0.30, -0.55, -0.10, 0, 230, //
  -0.30, -0.55, -0.10, 0, 234, //
  -0.30, -0.55, -0.10, 0, 242, //
  0, 0, 0, 1, 0,
];

Widget baseTiles() => ColorFiltered(
      colorFilter: _night ? const ColorFilter.matrix(_nightMatrix) : const ColorFilter.matrix(<double>[
        // grey scale, then lighter and softer
        0.20, 0.45, 0.08, 0, 70, //
        0.20, 0.45, 0.08, 0, 72, //
        0.20, 0.45, 0.08, 0, 76, //
        0, 0, 0, 1, 0,
      ]),
      child: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.mobility.app',
        maxNativeZoom: 19,
        keepBuffer: 4,
        tileDisplay: const TileDisplay.instantaneous(),
      ),
    );

/// Satellite photos (Esri World Imagery), switched with two taps on ◎.
Widget satelliteTiles() => TileLayer(
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.mobility.app',
      maxNativeZoom: 19,
      keepBuffer: 4,
      tileDisplay: const TileDisplay.instantaneous(),
    );
