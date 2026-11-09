import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places.dart';
import 'auth.dart';

/// Small persisted app state (local only for now; Firebase comes in M2).
/// The first start without an account: true while the start picture is on screen.
final ValueNotifier<bool> splashOn = ValueNotifier(false);

/// True while the first start runs (start picture, sign-in, vehicle). The map's guide waits for it.
final ValueNotifier<bool> startFlow = ValueNotifier(false);

/// Completes when [n] is false.
Future<void> whenOff(ValueNotifier<bool> n) {
  if (!n.value) return Future.value();
  final c = Completer<void>();
  void l() {
    if (!n.value) {
      n.removeListener(l);
      if (!c.isCompleted) c.complete();
    }
  }

  n.addListener(l);
  return c.future;
}

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
    // with Firebase set up, the signed-in user decides
    if (Auth.i.ready) hasAccount = Auth.i.user != null;
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

  Future<void> signOut() async {
    await Auth.i.signOut();
    hasAccount = false;
    await _p.setBool('hasAccount', false);
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
    await Auth.i.signOut();
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
