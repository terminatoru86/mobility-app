import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

enum PlaceType {
  rack,
  parkOutdoor,
  parkCovered,
  parkPrivate,
  pump,
  selfService,
  wash,
  charging,
  service,
  shop,
  sharing,
  rent,
  bmx,
}

enum Status { free, almost, full, unknown, neutral }

enum Vehicle { bike, ebike, scooter, moped, moto }

extension VehicleX on Vehicle {
  String get asset => switch (this) {
        Vehicle.bike => 'assets/vehicles/bike.jpg',
        Vehicle.ebike => 'assets/vehicles/ebike.jpg',
        Vehicle.scooter => 'assets/vehicles/scooter.jpg',
        Vehicle.moped => 'assets/vehicles/moped.jpg',
        Vehicle.moto => 'assets/vehicles/moto.jpg',
      };
  String get label => switch (this) {
        Vehicle.bike => 'Bike',
        Vehicle.ebike => 'E-bike',
        Vehicle.scooter => 'Scooter',
        Vehicle.moped => 'Moped',
        Vehicle.moto => 'Motorcycle',
      };
}

extension PlaceTypeX on PlaceType {
  String get glyph => 'assets/glyphs/${switch (this) {
        PlaceType.rack => 'rack',
        PlaceType.parkOutdoor => 'park',
        PlaceType.parkCovered => 'roof',
        PlaceType.parkPrivate => 'priv',
        PlaceType.pump => 'pump',
        PlaceType.selfService => 'self',
        PlaceType.wash => 'wash',
        PlaceType.charging => 'charge',
        PlaceType.service => 'service',
        PlaceType.shop => 'shop',
        PlaceType.sharing => 'share',
        PlaceType.rent => 'rent',
        PlaceType.bmx => 'bmx',
      }}.svg';

  String get title => switch (this) {
        PlaceType.rack => 'Bike rack',
        PlaceType.parkOutdoor => 'Outdoor parking',
        PlaceType.parkCovered => 'Covered parking',
        PlaceType.parkPrivate => 'Private parking',
        PlaceType.pump => 'Air pump',
        PlaceType.selfService => 'Self-service station',
        PlaceType.wash => 'Bike wash',
        PlaceType.charging => 'Charging station',
        PlaceType.service => 'Service hub',
        PlaceType.shop => 'Shop',
        PlaceType.sharing => 'Sharing',
        PlaceType.rent => 'Rent',
        PlaceType.bmx => 'Kids & BMX',
      };

  /// Places without a live status (rating instead of a count on the pin).
  bool get isNeutral =>
      this == PlaceType.service || this == PlaceType.shop || this == PlaceType.rent || this == PlaceType.bmx;

  /// Filter group used by the quick filter chips.
  String get group => switch (this) {
        PlaceType.rack ||
        PlaceType.parkOutdoor ||
        PlaceType.parkCovered ||
        PlaceType.parkPrivate =>
          'Parking',
        PlaceType.charging => 'Charging',
        PlaceType.service || PlaceType.pump || PlaceType.selfService || PlaceType.wash => 'Service',
        PlaceType.shop || PlaceType.rent || PlaceType.bmx => 'Shop',
        PlaceType.sharing => 'Sharing',
      };
}

class StatusColors {
  final Color main, tint, dark;
  const StatusColors(this.main, this.tint, this.dark);
}

StatusColors colorsFor(Status s) => switch (s) {
      Status.free => const StatusColors(AppColors.green, AppColors.greenTint, AppColors.greenDark),
      Status.almost => const StatusColors(AppColors.yellow, AppColors.yellowTint, AppColors.yellowDark),
      Status.full => const StatusColors(AppColors.red, AppColors.redTint, AppColors.redDark),
      Status.unknown => const StatusColors(AppColors.grey, AppColors.greyTint, AppColors.greyDark),
      Status.neutral => const StatusColors(AppColors.slate, AppColors.slateTint, AppColors.primary),
    };

class Review {
  final int stars;
  final String text;
  final String when;
  const Review(this.stars, this.text, this.when);
}

class QA {
  final String q;
  final String a;
  const QA(this.q, this.a);
}

class Security {
  final bool cameras, lighting, guard, access, overnight;
  final bool codeAccess;
  const Security({
    this.cameras = false,
    this.lighting = false,
    this.guard = false,
    this.access = false,
    this.overnight = false,
    this.codeAccess = false,
  });
}

class Operator {
  final String name;
  final String price;
  final bool inArea;
  const Operator(this.name, this.price, this.inArea);
}

class Place {
  final String id;
  final PlaceType type;
  final String address;
  final LatLng pos;
  final Status status;
  final String? count; // number shown top-right of the pin
  final String age; // time since last confirmation, e.g. "<5 min"
  final List<Vehicle> accepts;
  final String distance;
  final Map<Vehicle, int> etaMin;
  final String? hours;
  final String? phone;
  final double rating;
  final int reviewCount;
  final List<Review> reviews;
  final Security? security;
  final List<QA> qa;
  final String? tag; // e.g. "Automatic", "⚡ Type 2"
  final List<String> tools;
  final List<int> busy; // 12 values, 7:00-22:00
  final String? priceNow;
  final String? operatorName;
  final String? operatorPrice;

  const Place({
    required this.id,
    required this.type,
    required this.address,
    required this.pos,
    required this.status,
    this.count,
    this.age = '<5 min',
    this.accepts = const [Vehicle.bike, Vehicle.scooter],
    required this.distance,
    required this.etaMin,
    this.hours,
    this.phone,
    this.rating = 4.3,
    this.reviewCount = 20,
    this.reviews = const [],
    this.security,
    this.qa = const [],
    this.tag,
    this.tools = const [],
    this.busy = const [],
    this.priceNow,
    this.operatorName,
    this.operatorPrice,
  });

  Status get shownStatus => type.isNeutral ? Status.neutral : status;
}

/// Demo data around the Chicago Loop. Real data comes later (Firestore + GBFS).
const LatLng kUserPos = LatLng(41.8840, -87.6290);

const _rv = [
  Review(4, 'Always a free spot in the morning.', '2 days ago'),
  Review(5, 'Well lit, close to the train.', '4 days ago'),
  Review(4, 'Busy after 5 pm.', '1 week ago'),
];

const List<Place> demoPlaces = [
  Place(
    id: 'r1', type: PlaceType.rack, address: '41.8857, -87.6310', pos: LatLng(41.8857, -87.6310),
    status: Status.free, count: '8', distance: '1.2 km', etaMin: {Vehicle.bike: 6, Vehicle.scooter: 5},
    reviews: _rv, rating: 4.3, reviewCount: 37,
  ),
  Place(
    id: 'r2', type: PlaceType.rack, address: '41.8812, -87.6271', pos: LatLng(41.8812, -87.6271),
    status: Status.full, count: '0', age: '<1 h', distance: '0.5 km', etaMin: {Vehicle.bike: 3, Vehicle.scooter: 2},
    reviews: _rv,
  ),
  Place(
    id: 'p1', type: PlaceType.parkOutdoor, address: 'Daley Plaza, 50 W Washington St', pos: LatLng(41.8836, -87.6302),
    status: Status.free, count: '5', distance: '0.4 km', accepts: [Vehicle.bike, Vehicle.scooter, Vehicle.moped],
    etaMin: {Vehicle.bike: 3, Vehicle.scooter: 2, Vehicle.moped: 2}, hours: '24/7',
    busy: [10, 15, 30, 55, 70, 60, 45, 50, 80, 95, 70, 40], reviews: _rv, rating: 4.1, reviewCount: 22,
  ),
  Place(
    id: 'p2', type: PlaceType.parkCovered, address: '233 N Michigan Ave', pos: LatLng(41.8866, -87.6247),
    status: Status.almost, count: '2', age: '<15 min', distance: '1.1 km',
    accepts: [Vehicle.bike, Vehicle.scooter, Vehicle.moped], etaMin: {Vehicle.bike: 5, Vehicle.scooter: 4, Vehicle.moped: 3},
    hours: '6:00–23:00', busy: [20, 30, 45, 60, 75, 80, 70, 65, 90, 85, 60, 30],
    security: Security(cameras: true, lighting: true, guard: false, access: true, overnight: true),
    reviews: _rv, rating: 4.4, reviewCount: 51,
  ),
  Place(
    id: 'p3', type: PlaceType.parkPrivate, address: '12 N Wacker Dr', pos: LatLng(41.8823, -87.6372),
    status: Status.full, count: '0', age: '<15 min', distance: '0.9 km', accepts: [Vehicle.bike, Vehicle.scooter],
    etaMin: {Vehicle.bike: 4, Vehicle.scooter: 3}, hours: '7:00–22:00', phone: '(312) 555-0110',
    busy: [40, 40, 60, 100, 100, 80, 80, 100, 100, 60, 40, 40], priceNow: '\$5 / h',
    security: Security(cameras: true, lighting: true, guard: true, codeAccess: true, overnight: true),
    qa: [
      QA('Can I leave my bike overnight?', 'Yes, with a monthly pass.'),
      QA('Are there showers?', 'Lockers yes, showers no.'),
      QA('Can I pay by card?', 'Yes, at the entrance.'),
    ],
    reviews: _rv, rating: 4.2, reviewCount: 19,
  ),
  Place(
    id: 'u1', type: PlaceType.pump, address: 'Millennium Park, 201 E Randolph St', pos: LatLng(41.8840, -87.6216),
    status: Status.almost, age: '<1 h', distance: '450 m', etaMin: {Vehicle.bike: 3, Vehicle.scooter: 2},
    reviews: _rv, rating: 4.0, reviewCount: 12,
  ),
  Place(
    id: 's1', type: PlaceType.selfService, address: '41.8790, -87.6330', pos: LatLng(41.8790, -87.6330),
    status: Status.free, age: '<15 min', distance: '0.7 km', etaMin: {Vehicle.bike: 4, Vehicle.scooter: 3},
    tools: ['🔧 Tools', '💨 Pump', '🪝 Stand'], reviews: _rv, rating: 4.8, reviewCount: 9,
  ),
  Place(
    id: 'w1', type: PlaceType.wash, address: 'Lakeshore Trail', pos: LatLng(41.8875, -87.6170),
    status: Status.free, distance: '0.9 km', accepts: [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto],
    etaMin: {Vehicle.bike: 5, Vehicle.scooter: 4, Vehicle.moped: 3, Vehicle.moto: 3}, tag: 'Automatic',
    busy: [5, 10, 20, 35, 60, 70, 50, 40, 45, 55, 30, 15], reviews: _rv, rating: 4.6, reviewCount: 128,
  ),
  Place(
    id: 'c1', type: PlaceType.charging, address: '151 N Randolph St', pos: LatLng(41.8848, -87.6340),
    status: Status.almost, count: '1/4', distance: '0.8 km',
    accepts: [Vehicle.ebike, Vehicle.scooter, Vehicle.moped, Vehicle.moto],
    etaMin: {Vehicle.ebike: 4, Vehicle.scooter: 3, Vehicle.moped: 2, Vehicle.moto: 2}, tag: '⚡ Type 2',
    busy: [10, 20, 35, 50, 60, 75, 70, 65, 85, 90, 60, 30], reviews: _rv, rating: 4.5, reviewCount: 33,
  ),
  Place(
    id: 'v1', type: PlaceType.service, address: '1 E Grand Ave', pos: LatLng(41.8917, -87.6278),
    status: Status.neutral, distance: '2.4 km', accepts: [Vehicle.bike, Vehicle.scooter, Vehicle.moped],
    etaMin: {Vehicle.bike: 11, Vehicle.scooter: 9, Vehicle.moped: 6}, hours: '9:00–19:00', phone: '(312) 555-0141',
    rating: 4.7, reviewCount: 128, reviews: _rv,
    qa: [
      QA('Do they fix e-bikes?', 'Yes, motor and battery too.'),
      QA('Do I need an appointment?', 'Not for small repairs.'),
      QA('Are there showers for riders?', 'No.'),
    ],
  ),
  Place(
    id: 'h1', type: PlaceType.shop, address: '24 W Lake St', pos: LatLng(41.8857, -87.6285),
    status: Status.neutral, distance: '0.6 km', etaMin: {Vehicle.bike: 3, Vehicle.scooter: 3},
    hours: '10:00–20:00', phone: '(312) 555-0177', rating: 4.4, reviewCount: 64, reviews: _rv,
  ),
  Place(
    id: 'x1', type: PlaceType.sharing, address: 'W Lake St & N Clark St', pos: LatLng(41.8856, -87.6316),
    status: Status.free, count: '3', age: '<1 min', distance: '0.2 km', accepts: [Vehicle.scooter, Vehicle.bike],
    etaMin: {Vehicle.scooter: 3, Vehicle.bike: 4}, operatorName: 'Lime', operatorPrice: '\$1 start + \$0.39/min',
    reviews: _rv, rating: 4.0, reviewCount: 25,
  ),
  Place(
    id: 'x2', type: PlaceType.sharing, address: '1 N State St', pos: LatLng(41.8820, -87.6278),
    status: Status.free, count: '4', age: '<5 min', distance: '0.6 km', accepts: [Vehicle.bike],
    etaMin: {Vehicle.bike: 3}, operatorName: 'Divvy', operatorPrice: '\$1 start + \$0.19/min',
    reviews: _rv, rating: 4.2, reviewCount: 40,
  ),
  Place(
    id: 'n1', type: PlaceType.rent, address: '600 E Grand Ave', pos: LatLng(41.8920, -87.6110),
    status: Status.neutral, distance: '1.1 km', accepts: [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto],
    etaMin: {Vehicle.bike: 6, Vehicle.scooter: 5, Vehicle.moped: 4, Vehicle.moto: 4}, hours: '8:00–20:00',
    phone: '(312) 555-0123', rating: 4.5, reviewCount: 86, reviews: _rv,
    qa: [
      QA('What do I need to rent?', 'A driver\'s license or ID and a card.'),
      QA('Is a helmet included?', 'Yes, free on request.'),
      QA('Can I return it elsewhere?', 'No, only here.'),
    ],
  ),
];

const List<Operator> demoOperators = [
  Operator('Divvy', '\$1 start + \$0.19/min', true),
  Operator('Lime', '\$1 start + \$0.39/min', true),
];
