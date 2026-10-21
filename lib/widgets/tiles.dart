import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Calm, light-grey version of the OpenStreetMap map, so our coloured pins
/// and the blue routes stand out. (Before launch: a provider with our own key.)
Widget baseTiles() => ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
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
