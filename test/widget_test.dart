import 'package:flutter_test/flutter_test.dart';
import 'package:mobility/data/osm.dart';
import 'package:mobility/data/places.dart';

void main() {
  test('demo places have an ETA for every accepted vehicle they show', () {
    for (final p in demoPlaces) {
      expect(p.etaMin.isNotEmpty, true, reason: p.id);
    }
  });

  test('OpenStreetMap bike parking becomes a covered parking place', () {
    final p = placeFromOsm({
      'id': 'node/1',
      'lat': 41.885,
      'lon': -87.63,
      'tags': {'amenity': 'bicycle_parking', 'covered': 'yes', 'capacity': '12'},
    });
    expect(p, isNotNull);
    expect(p!.type, PlaceType.parkCovered);
    expect(p.facts, contains('Capacity 12'));
  });
}
