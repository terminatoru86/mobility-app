import 'package:latlong2/latlong.dart';

/// A learn-to-ride program for children run by a city, its schools or a local organisation.
/// Each one was read on the organiser's own page (November 2026); dates and sign-up live there.
class RideClass {
  final String place; // the city or area
  final String who; // who runs it
  final String title; // what it is, a few words
  final String note; // two or three sentences, in our words
  final String url; // the organiser's page
  final LatLng pos;
  final double miles; // how far around [pos] it is the local program
  final bool free;
  const RideClass({
    required this.place,
    required this.who,
    required this.title,
    required this.note,
    required this.url,
    required this.pos,
    this.miles = 25,
    this.free = true,
  });

  /// the short line on buttons: "Free kids classes · City of Chicago"
  String get label => '${free ? 'Free kids classes' : 'Kids learn to ride'} · $place';
}

/// For everywhere else in the country: the program that runs inside schools.
const kNationalClass = RideClass(
  place: 'in schools nationwide',
  who: 'All Kids Bike · national nonprofit',
  title: 'Learn to ride in kindergarten PE',
  note: 'All Kids Bike brings a learn-to-ride program into kindergarten PE classes in public schools across the '
      'country, so every child learns at school. Ask your school if it already has it, or how to bring it.',
  url: 'https://allkidsbike.org/about-us/',
  pos: LatLng(39.5, -98.35),
  miles: 0,
);

const kRideClasses = <RideClass>[
  RideClass(
    place: 'City of Chicago',
    who: 'City of Chicago · CDOT SAFE Ambassadors',
    title: 'Free Learn to Ride classes',
    note: 'Every summer the city\'s SAFE Ambassadors teach children and adults to ride, from the very first try '
        'to riding with confidence. It is part of the free programs they run across Chicago.',
    url: 'https://chicago.gov/city/en/depts/cdot/supp_info/safe-ambassadors.html',
    pos: LatLng(41.8781, -87.6298),
  ),
  RideClass(
    place: 'New York City',
    who: 'Bike New York · with NYC DOT at Bike Bonanza days',
    title: 'Free Learn to Ride — Kids',
    note: 'A free two-hour class for children aged 5 and up who are ready for two wheels. Every youth class is free '
        'and open to everyone; Bike Bonanza days add a kids\' bike swap and helmet fitting.',
    url: 'https://www.bike.nyc/education/programs/',
    pos: LatLng(40.7128, -74.0060),
  ),
  RideClass(
    place: 'City of Boston',
    who: 'City of Boston · Boston Bikes',
    title: 'Free Youth Cycling Program',
    note: 'The city brings bikes, helmets and two instructors to schools and youth groups for one to three weeks: '
        'games, riding skills and group rides, grades K–12, free. Schools and groups ask to host it.',
    url: 'https://boston.gov/departments/boston-bikes/youth-cycling-program',
    pos: LatLng(42.3601, -71.0589),
  ),
  RideClass(
    place: 'City of Portland',
    who: 'Portland Bureau of Transportation · with schools and the Community Cycling Center',
    title: 'Free Neighborhood Bike Fairs',
    note: 'Free, for all ages: staff teach balance, steering and braking, with children\'s and adult bikes to borrow, '
        'a skills course, short group rides and free helmets fitted on the spot.',
    url: 'https://www.portland.gov/transportation/walking-biking-transit-safety/bikefairs',
    pos: LatLng(45.5152, -122.6784),
  ),
  RideClass(
    place: 'San Francisco',
    who: 'San Francisco Bicycle Coalition',
    title: 'Freedom from Training Wheels',
    note: 'Free drop-in sessions where small children learn to balance and pedal. Balance bikes, pedal bikes and '
        'helmets are there to use; best for the youngest, older children are welcome.',
    url: 'https://sfbike.org/events/category/bicycle-education/',
    pos: LatLng(37.7749, -122.4194),
    miles: 15,
  ),
  RideClass(
    place: 'Seattle area schools',
    who: 'Cascade Bicycle Club · Seattle, Edmonds and Highline public schools',
    title: 'Let\'s Go: bike lessons in PE class',
    note: 'Children in grades 3–5 learn to ride and to be safe on foot and by bike during PE, in five lessons. '
        'The bikes and helmets come with the program.',
    url: 'https://cascade.org/lets-go',
    pos: LatLng(47.6062, -122.3321),
    miles: 30,
    free: false, // taught at school; the page does not name a price
  ),
  RideClass(
    place: 'Philadelphia',
    who: 'Bicycle Coalition of Greater Philadelphia',
    title: 'Where children can learn to ride',
    note: 'The Bike Hub at Bartram\'s Garden lends bikes for free and holds learn-to-ride classes for kids and adults; '
        'Lil\' Philly Safety Village in Hunting Park is a car-free place for children to practise.',
    url: 'https://bicyclecoalition.org/resources/classes-rides/',
    pos: LatLng(39.9526, -75.1652),
    free: false, // free bike loans; the page does not say the classes are free
  ),
];

/// The program of the place the rider is in; the national one anywhere else.
RideClass classNear(LatLng at) {
  const d = Distance();
  RideClass? best;
  var bestM = double.infinity;
  for (final c in kRideClasses) {
    final m = d(at, c.pos);
    if (m <= c.miles * 1609.34 && m < bestM) {
      best = c;
      bestM = m;
    }
  }
  return best ?? kNationalClass;
}
