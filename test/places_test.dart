import 'package:flutter_test/flutter_test.dart';
import 'package:mobility/data/device_ledger.dart';
import 'package:mobility/data/fixit_help.dart';
import 'package:mobility/data/osm.dart';
import 'package:mobility/data/places.dart';
import 'package:mobility/data/zones.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

Place? osm(Map<String, dynamic> tags) => placeFromOsm({'id': 'node/9', 'lat': 41.88, 'lon': -87.63, 'tags': tags});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Racks and parking', () {
    test('a rack inside a private area is private parking, with who may use it and no invented price', () {
      final p = osm({'amenity': 'bicycle_parking', 'bicycle_parking': 'stands', 'access': 'private', 'private_area': 'parking'})!;
      expect(p.type, PlaceType.parkPrivate);
      expect(p.offers, contains('Private property'));
      expect(p.offers, contains('Residents / staff only'));
      expect(p.priceNow, isNull);
    });

    test('customers-only parking says so', () {
      final p = osm({'amenity': 'bicycle_parking', 'access': 'customers', 'private_area': 'shop'})!;
      expect(p.offers, contains('Customers only'));
    });

    test('a public rack stays a rack', () {
      expect(osm({'amenity': 'bicycle_parking', 'bicycle_parking': 'stands'})!.type, PlaceType.rack);
    });

    test('security comes from the map data; unknown stays unknown', () {
      final s = osm({'amenity': 'bicycle_parking', 'covered': 'yes', 'surveillance': 'yes', 'lit': 'no', 'opening_hours': '24/7'})!.security!;
      expect(s.cameras, true);
      expect(s.lighting, false);
      expect(s.guard, isNull);
      expect(s.overnight, true);
    });

    test('street photos only turn "unknown" into "yes"', () {
      const s = Security(cameras: null, lighting: false, guard: null, access: null, overnight: null);
      final w = s.withPhotos({'cameras', 'lighting'});
      expect(w.cameras, true);
      expect(w.lighting, false);
      expect(w.fromPhotos, {'cameras'});
    });
  });

  group('Shops, service, wash, rent', () {
    test('a bike-only shop sells only bikes', () {
      expect(osm({'shop': 'bicycle', 'name': 'Comrade Cycles'})!.accepts, [Vehicle.bike]);
    });

    test('a shop with e-bikes and scooters sells all three', () {
      final a = osm({'shop': 'bicycle', 'name': 'City E-Bike & Scooter'})!.accepts;
      expect(a, containsAll([Vehicle.bike, Vehicle.ebike, Vehicle.scooter]));
    });

    test('a motorcycle shop is for motorcycles', () {
      expect(osm({'shop': 'motorcycle', 'name': 'Chicago Harley'})!.accepts, contains(Vehicle.moto));
    });

    test('service shows what it repairs', () {
      final p = osm({'shop': 'bicycle', 'service:bicycle:repair': 'yes', 'service:bicycle:second_hand': 'yes'})!;
      expect(p.type, PlaceType.service);
      expect(p.offers, containsAll(['Repairs', 'Used bikes']));
    });

    test('wash: who washes', () {
      expect(osm({'amenity': 'bicycle_wash', 'automated': 'yes'})!.tag, 'Automatic');
      expect(osm({'amenity': 'bicycle_wash', 'self_service': 'yes'})!.tag, 'Self-wash');
      expect(osm({'amenity': 'bicycle_wash', 'self_service': 'no'})!.tag, 'Staff wash');
    });

    test('rent lists what is rented', () {
      final p = osm({'amenity': 'bicycle_rental', 'rental': 'city_bike;ebike;cargo_bike'})!;
      expect(p.offers, containsAll(['City bikes', 'E-bikes', 'Cargo bikes']));
    });

    test('a repair stand keeps its maker for Fixit help', () {
      expect(osm({'amenity': 'bicycle_repair_station', 'brand': 'Saris'})!.operatorName, 'Saris');
    });
  });

  group('Fixit help', () {
    test('only web links from a QR code are opened', () {
      expect(helpLink('https://www.dero.com/fixit'), isNotNull);
      expect(helpLink('www.saris.com/help')!.scheme, 'https');
      expect(helpLink('tel:123'), isNull);
      expect(helpLink('hello'), isNull);
    });

    test('Dero opens its own page; an unknown maker opens the general guide', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await guideFor('Dero')).url, contains('dero.com'));
      expect((await guideFor('Some maker')).url, kGeneralGuide.url);
    });
  });

  group('Free map areas belong to the phone', () {
    test('the phone record survives a round trip', () {
      final r = LedgerRecord([MapZone('Madison, WI', const LatLng(43.07, -89.4), added: DateTime(2026, 9, 1))], DateTime(2026, 10, 1), 2);
      final back = LedgerRecord.fromJson(r.toJson());
      expect(back.freeEver, 2);
      expect(back.zones.single.name, 'Madison, WI');
      expect(back.lastMove, DateTime(2026, 10, 1));
    });
  });
}
