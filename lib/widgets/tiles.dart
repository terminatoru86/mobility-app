import 'package:flutter_map/flutter_map.dart';

/// The basemap used on every map in the app: standard OpenStreetMap tiles.
/// (Fine for testing. Before launch we switch to a provider with our own key,
/// e.g. MapTiler or Stadia Maps, because OSM's servers are not for big apps.)
TileLayer baseTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.mobility.app',
      maxNativeZoom: 19,
      keepBuffer: 4,
      tileDisplay: const TileDisplay.instantaneous(),
    );
