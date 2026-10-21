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

/// [street]: the GPS guidance look, closer to real colours so streets, parks and
/// buildings are easy to read at high zoom.
Widget baseTiles({bool street = false}) => ColorFiltered(
      colorFilter: _night
          ? const ColorFilter.matrix(_nightMatrix)
          : street
              ? const ColorFilter.matrix(<double>[
                  // 60 % colour, same brightness
                  0.685, 0.286, 0.029, 0, 0, //
                  0.085, 0.886, 0.029, 0, 0, //
                  0.085, 0.286, 0.629, 0, 0, //
                  0, 0, 0, 1, 0,
                ])
              : const ColorFilter.matrix(<double>[
                  // soft grey: streets, parks and water still readable, pins stand out
                  0.26, 0.55, 0.09, 0, 38, //
                  0.25, 0.56, 0.09, 0, 40, //
                  0.24, 0.53, 0.13, 0, 46, //
                  0, 0, 0, 1, 0,
                ]),
      child: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        // if a tile does not come, the same tile from the German OpenStreetMap mirror
        fallbackUrl: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.mobility.app',
        maxNativeZoom: 19,
        keepBuffer: 6,
        panBuffer: 2,
        tileDisplay: const TileDisplay.instantaneous(),
      ),
    );

/// CyclOSM: the OpenStreetMap map drawn for cyclists (bike lanes, racks, repair stations, shops).
/// Free, run by OpenStreetMap France on donations; credit OpenStreetMap and CyclOSM.
Widget bikeTiles() => TileLayer(
      urlTemplate: 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c'],
      fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.mobility.app',
      maxNativeZoom: 19,
      keepBuffer: 6,
      panBuffer: 2,
      tileDisplay: const TileDisplay.instantaneous(),
    );

/// Satellite photos (Esri World Imagery), switched with two taps on ◎.
Widget satelliteTiles() => TileLayer(
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.mobility.app',
      maxNativeZoom: 19,
      keepBuffer: 4,
      tileDisplay: const TileDisplay.instantaneous(),
    );
