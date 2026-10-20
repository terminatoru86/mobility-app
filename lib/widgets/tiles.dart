import 'package:flutter_map/flutter_map.dart';

/// The light basemap used on every map in the app (OpenStreetMap data, CARTO style).
TileLayer baseTiles() => TileLayer(
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.mobility.app',
      maxNativeZoom: 19,
      keepBuffer: 4,
      tileDisplay: const TileDisplay.instantaneous(),
    );
