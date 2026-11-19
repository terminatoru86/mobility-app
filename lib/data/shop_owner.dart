import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'places.dart';

/// The page of a shop, kept by its owner (Firestore, collection `shops`, one document per place).
///
/// The owner picks the place, writes the contact, hours and photos, says what the shop sells and
/// can switch on a discount. Everyone else sees these only after the page is marked `verified`
/// (the MOBIlity team does that in the Firebase console), so nobody can take over a shop by claiming it.
class ShopPage {
  final String id; // the place id, as in the map data
  final String owner; // uid of the signed-in owner
  final bool verified;
  final String name, email, phone, hours;
  final List<String> sells; // Vehicle names: bike, ebike, scooter, moped, moto
  final List<String> photos; // small JPEGs, base64
  final bool discount;
  final String discountText; // "15% off"
  final List<String> discountOn; // New bikes · New accessories · Other
  final String discountOther; // what "Other" is, in the owner's words

  const ShopPage({
    required this.id,
    required this.owner,
    this.verified = false,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.hours = '',
    this.sells = const [],
    this.photos = const [],
    this.discount = false,
    this.discountText = '',
    this.discountOn = const [],
    this.discountOther = '',
  });

  static const discountKinds = ['New bikes', 'New accessories', 'Other'];

  ShopPage copy({
    bool? verified,
    String? name,
    String? email,
    String? phone,
    String? hours,
    List<String>? sells,
    List<String>? photos,
    bool? discount,
    String? discountText,
    List<String>? discountOn,
    String? discountOther,
  }) =>
      ShopPage(
        id: id,
        owner: owner,
        verified: verified ?? this.verified,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        hours: hours ?? this.hours,
        sells: sells ?? this.sells,
        photos: photos ?? this.photos,
        discount: discount ?? this.discount,
        discountText: discountText ?? this.discountText,
        discountOn: discountOn ?? this.discountOn,
        discountOther: discountOther ?? this.discountOther,
      );

  /// The line under the address: how much, and on what. Empty when there is no discount.
  String get discountLine {
    if (!discount) return '';
    final what = [
      for (final k in discountOn)
        if (k == 'Other') (discountOther.trim().isEmpty ? 'Other' : discountOther.trim()) else k,
    ];
    return [if (discountText.trim().isNotEmpty) discountText.trim(), if (what.isNotEmpty) what.join(', ')].join(' · ');
  }

  List<Vehicle> get sellsVehicles => [for (final v in Vehicle.values) if (sells.contains(v.name)) v];

  Map<String, dynamic> toFields() => {
        'owner': _s(owner),
        'verified': {'booleanValue': verified},
        'name': _s(name),
        'email': _s(email),
        'phone': _s(phone),
        'hours': _s(hours),
        'sells': _a(sells),
        'photos': _a(photos),
        'discount': {'booleanValue': discount},
        'discountText': _s(discountText),
        'discountOn': _a(discountOn),
        'discountOther': _s(discountOther),
      };

  static ShopPage? fromFields(String id, Map? f) {
    if (f == null) return null;
    String s(String k) => ((f[k] as Map?)?['stringValue'] as String?) ?? '';
    bool b(String k) => ((f[k] as Map?)?['booleanValue'] as bool?) ?? false;
    List<String> a(String k) => [
          for (final v in (((f[k] as Map?)?['arrayValue'] as Map?)?['values'] as List? ?? const []))
            if (v is Map && v['stringValue'] is String) v['stringValue'] as String,
        ];
    final owner = s('owner');
    if (owner.isEmpty) return null;
    return ShopPage(
      id: id,
      owner: owner,
      verified: b('verified'),
      name: s('name'),
      email: s('email'),
      phone: s('phone'),
      hours: s('hours'),
      sells: a('sells'),
      photos: a('photos'),
      discount: b('discount'),
      discountText: s('discountText'),
      discountOn: a('discountOn'),
      discountOther: s('discountOther'),
    );
  }

  static Map<String, dynamic> _s(String v) => {'stringValue': v};
  static Map<String, dynamic> _a(List<String> v) => {
        'arrayValue': {'values': [for (final x in v) _s(x)]}
      };
}

/// The request to run a place's page: who the owner is and which business it is. Kept in a private
/// collection (`shop_claims`): only the rider who sent it and the MOBIlity team can read it, never the
/// other riders. The team sets `status` to "approved" (or "rejected", with a `note`) in the console.
class ShopClaim {
  final String uid, placeKey, placeName, businessName, address, ownerName, phone, ein, status, note, code, checks;
  final double lat, lon;
  const ShopClaim({
    required this.uid,
    required this.placeKey,
    required this.placeName,
    required this.businessName,
    required this.address,
    required this.ownerName,
    required this.phone,
    required this.ein,
    this.status = 'pending',
    this.note = '',
    this.code = '',
    this.checks = '',
    this.lat = 0,
    this.lon = 0,
  });

  /// A short code the owner can write on the shop's website to prove it is theirs.
  static String newCode() {
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return 'MOBI-${List.generate(6, (_) => a[r.nextInt(a.length)]).join()}';
  }

  bool get approved => status == 'approved';
  bool get rejected => status == 'rejected';

  /// 12-3456789 → "••-•••6789" (the number is not shown again on screen)
  String get einHidden => ein.length < 4 ? '•••' : '••-•••${ein.substring(ein.length - 4)}';

  /// An EIN is nine digits, written 12-3456789.
  static String? einClean(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length == 9 ? '${d.substring(0, 2)}-${d.substring(2)}' : null;
  }

  static String? phoneClean(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 && d.length <= 15 ? v.trim() : null;
  }

  Map<String, dynamic> toFields() => {
        'uid': ShopPage._s(uid),
        'placeKey': ShopPage._s(placeKey),
        'placeName': ShopPage._s(placeName),
        'businessName': ShopPage._s(businessName),
        'address': ShopPage._s(address),
        'ownerName': ShopPage._s(ownerName),
        'phone': ShopPage._s(phone),
        'ein': ShopPage._s(ein),
        'status': ShopPage._s('pending'),
        'note': ShopPage._s(note),
        'code': ShopPage._s(code),
        'checks': ShopPage._s(''),
        'lat': {'doubleValue': lat},
        'lon': {'doubleValue': lon},
        'at': {'integerValue': '${DateTime.now().millisecondsSinceEpoch}'},
      };

  static ShopClaim? fromFields(Map? f) {
    if (f == null) return null;
    String s(String k) => ((f[k] as Map?)?['stringValue'] as String?) ?? '';
    if (s('uid').isEmpty) return null;
    return ShopClaim(
      uid: s('uid'),
      placeKey: s('placeKey'),
      placeName: s('placeName'),
      businessName: s('businessName'),
      address: s('address'),
      ownerName: s('ownerName'),
      phone: s('phone'),
      ein: s('ein'),
      status: s('status').isEmpty ? 'pending' : s('status'),
      note: s('note'),
      code: s('code'),
      checks: s('checks'),
    );
  }
}

/// A message from a shop to the riders who came in.
class ShopMessage {
  final String shop, text;
  final DateTime at;
  const ShopMessage(this.shop, this.text, this.at);
}

/// "2026-11" as 202611: the id of the month's message. Counted in UTC, the same as the server rules.
int monthId([DateTime? t]) {
  final u = (t ?? DateTime.now()).toUtc();
  return u.year * 100 + u.month;
}

String shopKey(String placeId) => placeId.replaceAll('/', '_');

class ShopPages extends ChangeNotifier {
  ShopPages._();
  static final ShopPages i = ShopPages._();

  final Map<String, (ShopPage?, int)> _cache = {}; // place -> (page, when read)
  static const _ttlMin = 10;

  Uri? _uri(String path, [Map<String, String>? query]) {
    if (!Auth.i.ready) return null;
    try {
      final o = Firebase.app().options;
      return Uri.https('firestore.googleapis.com', '/v1/projects/${o.projectId}/databases/(default)/documents$path',
          {'key': o.apiKey, ...?query});
    } catch (_) {
      return null;
    }
  }

  bool get isSignedIn => Auth.i.user != null;

  Future<Map<String, String>?> _auth() async {
    final t = await Auth.i.user?.getIdToken();
    return t == null ? null : {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
  }

  /// The page of a place, or null. Others see it only once it is verified; its owner always sees it.
  Future<ShopPage?> of(String placeId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hit = _cache[shopKey(placeId)];
    if (hit != null && now - hit.$2 < _ttlMin * 60000) return _visible(hit.$1);
    final u = _uri('/shops/${shopKey(placeId)}');
    if (u == null) return null;
    try {
      final r = await http.get(u).timeout(const Duration(seconds: 6));
      if (r.statusCode == 404) {
        _cache[shopKey(placeId)] = (null, now);
        return null;
      }
      if (r.statusCode != 200) return null;
      final page = ShopPage.fromFields(placeId, (jsonDecode(r.body) as Map)['fields'] as Map?);
      _cache[shopKey(placeId)] = (page, now);
      return _visible(page);
    } catch (_) {
      return null;
    }
  }

  ShopPage? _visible(ShopPage? p) => p != null && (p.verified || p.owner == Auth.i.user?.uid) ? p : null;

  /// What the map already knows from the page, with no waiting: used by filters and search.
  ShopPage? cached(String placeId) {
    final c = _cache[shopKey(placeId)];
    return c == null ? null : _visible(c.$1);
  }

  /// The signed-in rider's request, or null when none was sent yet.
  Future<ShopClaim?> myClaim() async {
    final uid = Auth.i.user?.uid;
    final u = _uri(':runQuery');
    final h = await _auth();
    if (uid == null || u == null || h == null) return null;
    try {
      final r = await http
          .post(u,
              headers: h,
              body: jsonEncode({
                'structuredQuery': {
                  'from': [
                    {'collectionId': 'shop_claims'}
                  ],
                  'where': {
                    'fieldFilter': {
                      'field': {'fieldPath': 'uid'},
                      'op': 'EQUAL',
                      'value': {'stringValue': uid}
                    }
                  },
                  'limit': 1,
                }
              }))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      for (final row in jsonDecode(r.body) as List) {
        final d = (row as Map)['document'] as Map?;
        if (d != null) return ShopClaim.fromFields(d['fields'] as Map?);
      }
    } catch (_) {}
    return null;
  }

  /// Sends (or sends again, after a refusal) the request for a place. False when the place was already
  /// asked for by someone else.
  Future<bool> submitClaim(ShopClaim c) async {
    final u = _uri('/shop_claims/${c.placeKey}');
    final h = await _auth();
    if (u == null || h == null) return false;
    try {
      final r = await http.patch(u, headers: h, body: jsonEncode({'fields': c.toFields()})).timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The shops of the signed-in rider (usually one).
  Future<List<ShopPage>> mine() async {
    final uid = Auth.i.user?.uid;
    final u = _uri(':runQuery');
    if (uid == null || u == null) return const [];
    try {
      final r = await http
          .post(u,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'structuredQuery': {
                  'from': [
                    {'collectionId': 'shops'}
                  ],
                  'where': {
                    'fieldFilter': {
                      'field': {'fieldPath': 'owner'},
                      'op': 'EQUAL',
                      'value': {'stringValue': uid}
                    }
                  },
                  'limit': 5,
                }
              }))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const [];
      final out = <ShopPage>[];
      for (final row in jsonDecode(r.body) as List) {
        final d = (row as Map)['document'] as Map?;
        if (d == null) continue;
        final key = (d['name'] as String).split('/').last;
        final page = ShopPage.fromFields(key, d['fields'] as Map?);
        if (page != null) out.add(page);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Saves the page (creates it the first time; then it waits to be verified). The place id is stored
  /// with `/` turned to `_` in the document name, so `placeId` here is the key.
  Future<bool> save(ShopPage p, String placeId) async {
    final u = _uri('/shops/${shopKey(placeId)}');
    final h = await _auth();
    if (u == null || h == null) return false;
    try {
      final r = await http.patch(u, headers: h, body: jsonEncode({'fields': p.toFields()})).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        _cache[shopKey(placeId)] = (p, DateTime.now().millisecondsSinceEpoch);
        notifyListeners();
        return true;
      }
      debugPrint('shop save ${r.statusCode}: ${r.body}');
    } catch (e) {
      debugPrint('shop save failed: $e');
    }
    return false;
  }

  // ── visits and rewards ──────────────────────────────────────────────────────

  static const _visitedKey = 'shop_visited_v1'; // "key|name" of the shops the rider has been in

  Future<List<String>> visitedShops() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_visitedKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> visited(String placeId) async => (await visitedShops()).any((e) => e.startsWith('${shopKey(placeId)}|'));

  static const doorMeters = 120.0;

  /// "I was here": only close to the shop, only when signed in, once per shop. The shop can then
  /// send this rider a message (once a month at most); the shop never sees who the riders are.
  Future<bool> checkIn(Place p, ShopPage page, LatLng me) async {
    if (const Distance()(me, p.pos) > doorMeters) return false;
    final uid = Auth.i.user?.uid;
    final u = _uri('/shops/${shopKey(p.id)}/visits/$uid');
    final h = await _auth();
    if (uid == null || u == null || h == null) return false;
    try {
      final r = await http
          .patch(u, headers: h, body: jsonEncode({'fields': {'at': {'integerValue': '${DateTime.now().millisecondsSinceEpoch}'}}}))
          .timeout(const Duration(seconds: 8));
      // 403 = already counted before: fine
      if (r.statusCode != 200 && r.statusCode != 403) return false;
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_visitedKey) ?? [];
      final k = shopKey(p.id);
      if (!list.any((e) => e.startsWith('$k|'))) {
        list.add('$k|${page.name.isEmpty ? p.address : page.name}');
        await prefs.setStringList(_visitedKey, list);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// How many riders have checked in at this shop (owner only).
  Future<int> visitCount(String placeId) async {
    final u = _uri('/shops/${shopKey(placeId)}/visits', {'pageSize': '300'});
    final h = await _auth();
    if (u == null || h == null) return 0;
    try {
      final r = await http.get(u, headers: h).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return 0;
      return ((jsonDecode(r.body) as Map)['documents'] as List?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// True when this month's message was already sent (one per shop per month).
  Future<bool> sentThisMonth(String placeId) async {
    final u = _uri('/shops/${shopKey(placeId)}/rewards/${monthId()}');
    final h = await _auth();
    if (u == null || h == null) return false;
    try {
      final r = await http.get(u, headers: h).timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends one message to every rider who checked in. The document is named after the month and the
  /// server refuses a second one in the same month (and anything but the owner writing it).
  Future<bool> sendReward(String placeId, String shopName, String text) async {
    final u = _uri('/shops/${shopKey(placeId)}/rewards/${monthId()}');
    final h = await _auth();
    if (u == null || h == null) return false;
    try {
      final r = await http
          .patch(u,
              headers: h,
              body: jsonEncode({
                'fields': {
                  'text': {'stringValue': text.trim()},
                  'shop': {'stringValue': shopName},
                  'at': {'integerValue': '${DateTime.now().millisecondsSinceEpoch}'},
                }
              }))
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The messages from the shops this rider has been in, newest first.
  Future<List<ShopMessage>> inbox() async {
    final out = <ShopMessage>[];
    final h = await _auth();
    if (h == null) return out;
    for (final e in await visitedShops()) {
      final k = e.split('|').first;
      final u = _uri('/shops/$k/rewards', {'pageSize': '12'});
      if (u == null) continue;
      try {
        final r = await http.get(u, headers: h).timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) continue;
        for (final d in ((jsonDecode(r.body) as Map)['documents'] as List? ?? const [])) {
          final f = (d as Map)['fields'] as Map? ?? const {};
          final text = ((f['text'] as Map?)?['stringValue'] as String?) ?? '';
          final shop = ((f['shop'] as Map?)?['stringValue'] as String?) ?? e.split('|').last;
          final at = int.tryParse('${(f['at'] as Map?)?['integerValue'] ?? ''}') ?? 0;
          if (text.isNotEmpty) out.add(ShopMessage(shop, text, DateTime.fromMillisecondsSinceEpoch(at)));
        }
      } catch (_) {}
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }
}
