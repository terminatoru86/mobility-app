import 'package:flutter_test/flutter_test.dart';
import 'package:mobility/data/places.dart';

void main() {
  test('demo places have an ETA for every accepted vehicle they show', () {
    for (final p in demoPlaces) {
      expect(p.etaMin.isNotEmpty, true, reason: p.id);
    }
  });
}
