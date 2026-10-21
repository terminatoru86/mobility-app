import 'package:latlong2/latlong.dart';

/// A map area the rider can use: 100 miles around a city.
/// Two areas are free (they come by themselves where the rider lives, studies or works);
/// any other area is unlocked with a small payment.
class MapZone {
  final String name;
  final LatLng center;
  final bool paid;
  final DateTime added;
  final DateTime? until; // paid areas: end of the pass
  const MapZone(this.name, this.center, {this.paid = false, required this.added, this.until});

  static const radiusMiles = 100;
  static const radiusMeters = 160934.0;
  static const maxFree = 2;
  static const price = '\$1';
  static const passDays = 30;
  static const moveEveryDays = 90; // a free area can be moved (new home, new job) this often

  bool get active => until == null || DateTime.now().isBefore(until!);
  int get daysLeft => until == null ? 0 : until!.difference(DateTime.now()).inDays + 1;
  bool covers(LatLng p) => active && const Distance()(center, p) <= radiusMeters;

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': [center.latitude, center.longitude],
        'p': paid,
        'a': added.millisecondsSinceEpoch,
        if (until != null) 'u': until!.millisecondsSinceEpoch,
      };

  static MapZone fromJson(Map<String, dynamic> j) => MapZone(
        j['n'] as String,
        LatLng((j['c'][0] as num).toDouble(), (j['c'][1] as num).toDouble()),
        paid: j['p'] as bool? ?? false,
        added: DateTime.fromMillisecondsSinceEpoch(j['a'] as int),
        until: j['u'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['u'] as int),
      );
}
