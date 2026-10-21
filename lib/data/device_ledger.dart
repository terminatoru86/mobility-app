import 'dart:convert';
import 'dart:math' as math;

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'zones.dart';

/// The map areas belong to the PHONE, not to the account or the install.
///
/// Uninstalling and installing again (or a new account) must not give two new free areas:
/// the phone keeps its record, and a third area always asks for the payment.
///
/// Where the phone's record lives:
///  1. the phone's id: Android ID on Android (the same after a reinstall of our app),
///     a random id kept in the Keychain on iPhone (the Keychain stays after a reinstall);
///  2. a copy of the areas in the phone's secure storage (Keychain on iPhone);
///  3. our server ([kLedgerUrl]), which has the last word: it keeps at most 2 free areas per phone
///     and the 90-day rule for moving one. Only a hash of the id leaves the phone.
///
/// Until the server exists (Firebase project), 1 and 2 already protect iPhones;
/// on Android the server is what remembers after a reinstall.
const String? kLedgerUrl = null; // e.g. 'https://us-central1-<project>.cloudfunctions.net/zoneLedger'

class DeviceLedger {
  DeviceLedger._();
  static final i = DeviceLedger._();

  static const _salt = 'MOBIlity-zones-v1';
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // stays after the app is deleted, never copied to another phone
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  String? _key;

  /// A hash of the phone's id (the same after a reinstall). The real id never leaves the phone.
  Future<String> deviceKey() async {
    if (_key != null) return _key!;
    String? raw;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        raw = await const AndroidId().getId();
      }
    } catch (_) {}
    if (raw == null || raw.isEmpty) {
      // iPhone and browser: our own random id, kept in the Keychain / secure storage
      try {
        raw = await _secure.read(key: 'device_id');
        if (raw == null) {
          final r = math.Random.secure();
          raw = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
          await _secure.write(key: 'device_id', value: raw);
        }
      } catch (_) {
        raw = 'unknown';
      }
    }
    return _key = sha256.convert(utf8.encode('$_salt:$raw')).toString();
  }

  /// The phone's record: its areas and when a free area was last moved.
  Future<LedgerRecord?> read() async {
    final key = await deviceKey();
    final server = await _call({'action': 'get', 'device': key});
    if (server != null) {
      await _saveLocal(server);
      return server;
    }
    try {
      final s = await _secure.read(key: 'zones_ledger');
      return s == null ? null : LedgerRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Saves the phone's record. Returns the server's record when it answers
  /// (it may refuse a third free area: then its list is the one to keep).
  Future<LedgerRecord?> write(LedgerRecord r) async {
    await _saveLocal(r);
    final key = await deviceKey();
    final server = await _call({'action': 'put', 'device': key, 'record': r.toJson()});
    if (server != null) await _saveLocal(server);
    return server;
  }

  Future<void> _saveLocal(LedgerRecord r) async {
    try {
      await _secure.write(key: 'zones_ledger', value: jsonEncode(r.toJson()));
    } catch (_) {}
  }

  Future<LedgerRecord?> _call(Map<String, dynamic> body) async {
    final url = kLedgerUrl;
    if (url == null) return null;
    try {
      final res = await http
          .post(Uri.parse(url), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return LedgerRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Ledger offline: $e');
      return null;
    }
  }
}

class LedgerRecord {
  final List<MapZone> zones; // free and paid areas of this phone
  final DateTime? lastMove;
  final int freeEver; // how many free areas this phone has ever claimed (moves do not count)
  const LedgerRecord(this.zones, this.lastMove, this.freeEver);

  Map<String, dynamic> toJson() => {
        'zones': [for (final z in zones) z.toJson()],
        if (lastMove != null) 'lastMove': lastMove!.millisecondsSinceEpoch,
        'freeEver': freeEver,
      };

  static LedgerRecord fromJson(Map<String, dynamic> j) => LedgerRecord(
        [
          for (final z in (j['zones'] as List? ?? const []))
            MapZone.fromJson(Map<String, dynamic>.from(z as Map)),
        ],
        j['lastMove'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['lastMove'] as num).toInt()),
        (j['freeEver'] as num?)?.toInt() ?? 0,
      );
}
