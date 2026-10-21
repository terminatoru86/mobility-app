import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Our places database on the phone.
///
/// The app ships with the whole US inside (assets/osm/tiles). Once a week it asks our data site
/// which 1° pieces changed and downloads only those, for the rider's areas; they are kept here and
/// used instead of the shipped ones. Phone: files in the app folder. Web: browser storage.
class PlaceDb {
  PlaceDb._();
  static final PlaceDb i = PlaceDb._();

  /// Where our data packs are published (built twice a month from OpenStreetMap + city halls).
  static const site = 'https://terminatoru86.github.io/mobility-data/tiles/';
  static const checkEveryDays = 7;

  Map<String, String> _hashes = {}; // piece -> version we have on the phone
  DateTime? lastCheck;
  bool _ready = false;
  Directory? _dir;

  Future<void> open() async {
    if (_ready) return;
    _ready = true;
    try {
      if (!kIsWeb) {
        _dir = Directory('${(await getApplicationSupportDirectory()).path}/placedb');
        await _dir!.create(recursive: true);
      }
      final meta = await _readRaw('meta');
      if (meta != null) {
        final j = jsonDecode(meta) as Map<String, dynamic>;
        _hashes = ((j['tiles'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
        final lc = j['lastCheck'] as int?;
        if (lc != null) lastCheck = DateTime.fromMillisecondsSinceEpoch(lc);
      }
    } catch (e) {
      debugPrint('PlaceDb open failed: $e');
    }
  }

  String? hashOf(String key) => _hashes[key];
  bool get checkDue => lastCheck == null || DateTime.now().difference(lastCheck!).inDays >= checkEveryDays;

  Future<String?> read(String key) => _readRaw('t_$key');

  Future<void> write(String key, String json, String hash) async {
    try {
      await _writeRaw('t_$key', json);
      _hashes[key] = hash;
      await _saveMeta();
    } catch (e) {
      debugPrint('PlaceDb write $key failed: $e'); // full storage: the shipped piece stays in use
    }
  }

  Future<void> checked() async {
    lastCheck = DateTime.now();
    await _saveMeta();
  }

  Future<void> _saveMeta() =>
      _writeRaw('meta', jsonEncode({'lastCheck': lastCheck?.millisecondsSinceEpoch, 'tiles': _hashes}));

  Future<String?> _readRaw(String name) async {
    try {
      if (kIsWeb) return (await SharedPreferences.getInstance()).getString('pdb_$name');
      final f = File('${_dir!.path}/$name.json');
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRaw(String name, String data) async {
    if (kIsWeb) {
      await (await SharedPreferences.getInstance()).setString('pdb_$name', data);
    } else {
      await File('${_dir!.path}/$name.json').writeAsString(data);
    }
  }
}
