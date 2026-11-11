import 'package:latlong2/latlong.dart';

/// A learn-to-ride program for children run by a city, its schools or a local organisation.
/// Each one was read on the organiser's own page (November 2026) and is kept only when that page
/// (or the organiser's listing) shows it running in 2024 or later; dates and sign-up live there.
class RideClass {
  final String place; // the city or area
  final String who; // who runs it
  final String title; // what it is, a few words
  final String note; // two or three sentences, in our words
  final String url; // the organiser's page
  final LatLng pos;
  final double miles; // how far around [pos] it is the local program
  final bool free;

  /// the latest year it was seen running on the organiser's page (only programs from 2024 on are kept)
  final int seen;
  const RideClass({
    required this.place,
    required this.who,
    required this.title,
    required this.note,
    required this.url,
    required this.pos,
    this.miles = 25,
    this.free = true,
    required this.seen,
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
  seen: 2026,
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
    seen: 2025,
  ),
  RideClass(
    place: 'New York City',
    who: 'Bike New York · with NYC DOT at Bike Bonanza days',
    title: 'Free Learn to Ride — Kids',
    note: 'A free two-hour class for children aged 5 and up who are ready for two wheels. Every youth class is free '
        'and open to everyone; Bike Bonanza days add a kids\' bike swap and helmet fitting.',
    url: 'https://www.bike.nyc/education/programs/',
    pos: LatLng(40.7128, -74.0060),
    seen: 2024,
  ),
  RideClass(
    place: 'City of Boston',
    who: 'City of Boston · Boston Bikes',
    title: 'Free Youth Cycling Program',
    note: 'The city brings bikes, helmets and two instructors to schools and youth groups for one to three weeks: '
        'games, riding skills and group rides, grades K–12, free. Schools and groups ask to host it.',
    url: 'https://boston.gov/departments/boston-bikes/youth-cycling-program',
    pos: LatLng(42.3601, -71.0589),
    seen: 2026,
  ),
  RideClass(
    place: 'City of Portland',
    who: 'Portland Bureau of Transportation · with schools and the Community Cycling Center',
    title: 'Free Neighborhood Bike Fairs',
    note: 'Free, for all ages: staff teach balance, steering and braking, with children\'s and adult bikes to borrow, '
        'a skills course, short group rides and free helmets fitted on the spot.',
    url: 'https://www.portland.gov/transportation/walking-biking-transit-safety/bikefairs',
    pos: LatLng(45.5152, -122.6784),
    seen: 2026,
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
    seen: 2025,
  ),
  RideClass(
    place: 'Seattle area schools',
    who: 'Cascade Bicycle Club · with Seattle DOT and the Seattle, Edmonds and Highline public schools',
    title: 'Let\'s Go: bike lessons in PE class',
    note: 'Children in grades 3–5 learn to ride and to be safe on foot and by bike during PE, in five lessons. '
        'The bikes and helmets come with the program.',
    url: 'https://cascade.org/lets-go',
    pos: LatLng(47.6062, -122.3321),
    miles: 30,
    free: false, // taught at school; the page does not name a price
    seen: 2024,
  ),
  RideClass(
    place: 'Philadelphia',
    who: 'Bicycle Coalition of Greater Philadelphia',
    title: 'Where children can learn to ride',
    note: 'The Bike Hub at Bartram\'s Garden lends bikes for free and holds Kids Learn to Ride sessions (ages 4–16); '
        'Lil\' Philly Safety Village in Hunting Park is a car-free place for children to practise.',
    url: 'https://bicyclecoalition.org/resources/classes-rides/',
    pos: LatLng(39.9526, -75.1652),
    free: false, // free bike loans; the page does not say the classes are free
    seen: 2025,
  ),
  RideClass(
    place: 'City of Phoenix',
    who: 'Phoenix Public Library · with Phoenix Children\'s',
    title: 'Free Bike Safety Rodeos',
    note: 'Free hands-on mornings at city libraries for elementary-age children: stopping, turning and the rules of '
        'the road. Bikes and scooters are there for those who need one; no sign-up needed.',
    url: 'https://www.phoenix.gov/newsroom/public-library-news/learn-bike-safety-at-phoenix-public-library-s-bike-safety-rodeos.html',
    pos: LatLng(33.4484, -112.0740),
    seen: 2026,
  ),
  RideClass(
    place: 'Pittsburgh',
    who: 'BikePGH · with the city\'s CitiParks and POGOH',
    title: 'Free Learn 2 Ride',
    note: 'Free group learn-to-ride classes at the Bud Harris Cycling Track for children 5–12 and for teens, with a '
        'walk-up balance-bike zone for the under-fives. Sign-up is needed for the classes.',
    url: 'https://bikepgh.org/2025/04/15/learn-2-ride-this-summer-at-the-bud-harris-cycling-track/',
    pos: LatLng(40.4406, -79.9959),
    seen: 2025,
  ),
  RideClass(
    place: 'Nashville',
    who: 'Bike Fun · with Metro Nashville Parks & Recreation',
    title: 'Free All Ages Learn to Ride',
    note: 'A free class at Shelby Bottoms for anyone aged 7 and up who has never ridden; a parent stays with children. '
        'Classes for five- to eight-year-olds are held separately, on a sliding fee.',
    url: 'https://events.humanitix.com/all-ages-learn-to-ride-september-2026',
    pos: LatLng(36.1627, -86.7816),
    seen: 2026,
  ),
  RideClass(
    place: 'Madison',
    who: 'Wisconsin Bike Fed',
    title: 'Free Family Learn to Ride',
    note: 'A free evening for the whole family, with teachers for children and for adults. Helmets and a few loaner '
        'bikes are there; sign-up is needed.',
    url: 'https://wisconsinbikefed.org/events/family-all-ages-learn-to-ride-madison/',
    pos: LatLng(43.0731, -89.4012),
    seen: 2026,
  ),
  RideClass(
    place: 'Miami',
    who: 'BikeSafe, University of Miami · at The Underline',
    title: 'Free Bike Rodeos',
    note: 'Free mornings on The Underline where children practise starting and stopping, balance, turns and hand '
        'signals with the university\'s BikeSafe team.',
    url: 'https://theunderline.org/events/bike-rodeos-bikesafe-the-underline-2',
    pos: LatLng(25.7617, -80.1918),
    seen: 2025,
  ),
  RideClass(
    place: 'City of Albuquerque',
    who: 'City of Albuquerque Parks & Recreation · Esperanza Bicycle Safety Education Center',
    title: 'Free Bicycle Safety Skills Class',
    note: 'A free one-hour class for all ages, with a helmet and safety gear included; the city also runs bike rodeos '
        'on balance and handling for 3rd to 5th graders. Sign-up is needed.',
    url: 'https://www.cabq.gov/parksandrecreation/recreation/bike/esperanza-bicycle-safety-education-center/hands-on-school-community-bike-education/bike-programing-offerings',
    pos: LatLng(35.0844, -106.6504),
    seen: 2026,
  ),
  RideClass(
    place: 'City of Tampa',
    who: 'City of Tampa',
    title: 'Free Tampa Kind Bike Rodeo',
    note: 'A free city bike-safety morning in a park: stopping, steering round obstacles and signalling. '
        'It teaches safe riding skills more than the very first pedal strokes.',
    url: 'https://tampa.gov/node/146051',
    pos: LatLng(27.9506, -82.4572),
    seen: 2024,
  ),
  RideClass(
    place: 'Atlanta',
    who: 'Propel ATL · for Atlanta Public Schools families',
    title: 'Free Bike Family program',
    note: 'Free classes with bikes and gear for Atlanta Public Schools students and their caregivers: a safety class '
        'and a group ride together. Families sign up for a cohort.',
    url: 'https://atlbike.nationbuilder.com/bikefamily',
    pos: LatLng(33.7490, -84.3880),
    seen: 2024,
  ),
  RideClass(
    place: 'Washington, DC area',
    who: 'National Park Service · George Washington Memorial Parkway',
    title: 'Learn to Ride with the park rangers',
    note: 'The park teaches children aged 5 and up to ride. The 2026 classes filled up; the park keeps a waiting '
        'list and opens new dates on its page.',
    url: 'https://home.nps.gov/gwmp/planyourvisit/learntoride.htm',
    pos: LatLng(38.9072, -77.0369),
    miles: 20,
    free: false, // the page does not name a price
    seen: 2026,
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
