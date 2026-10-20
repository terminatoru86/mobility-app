import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places.dart';

/// Small persisted app state (local only for now; Firebase comes in M2).
class AppState extends ChangeNotifier {
  late SharedPreferences _p;

  int opens = 0;
  bool guideDone = false;
  bool sheetTipDone = false;
  bool sharingChosen = false;
  bool hasAccount = false;
  Vehicle? myVehicle;
  String model = '';

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    opens = (_p.getInt('opens') ?? 0) + 1; // counts cold starts only
    await _p.setInt('opens', opens);
    guideDone = _p.getBool('guideDone') ?? false;
    sheetTipDone = _p.getBool('sheetTipDone') ?? false;
    sharingChosen = _p.getBool('sharingChosen') ?? false;
    hasAccount = _p.getBool('hasAccount') ?? false;
    final v = _p.getString('myVehicle');
    myVehicle = v == null ? null : Vehicle.values.where((e) => e.name == v).firstOrNull;
    model = _p.getString('model') ?? '';
  }

  /// Account invite: 3rd open, then every 10 opens (13, 23, …) until an account exists.
  bool get shouldInvite => !hasAccount && guideDone && opens >= 3 && (opens - 3) % 10 == 0;

  Future<void> setGuideDone() async {
    guideDone = true;
    await _p.setBool('guideDone', true);
    notifyListeners();
  }

  Future<void> setSheetTipDone() async {
    sheetTipDone = true;
    await _p.setBool('sheetTipDone', true);
    notifyListeners();
  }

  Future<void> setSharingChosen() async {
    sharingChosen = true;
    await _p.setBool('sharingChosen', true);
    notifyListeners();
  }

  Future<void> createAccount() async {
    hasAccount = true;
    await _p.setBool('hasAccount', true);
    notifyListeners();
  }

  Future<void> saveVehicle(Vehicle? v, String m) async {
    myVehicle = v;
    model = m;
    if (v == null) {
      await _p.remove('myVehicle');
    } else {
      await _p.setString('myVehicle', v.name);
    }
    await _p.setString('model', m);
    notifyListeners();
  }

  /// For testing on the phone: start over as a new user.
  Future<void> resetDemo() async {
    await _p.clear();
    opens = 1;
    await _p.setInt('opens', 1);
    guideDone = false;
    sheetTipDone = false;
    sharingChosen = false;
    hasAccount = false;
    myVehicle = null;
    model = '';
    notifyListeners();
  }

  Future<void> replayGuide() async {
    guideDone = false;
    sheetTipDone = false;
    await _p.setBool('guideDone', false);
    await _p.setBool('sheetTipDone', false);
    notifyListeners();
  }
}
