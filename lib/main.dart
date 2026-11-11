import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'data/auth.dart';
import 'data/places.dart';
import 'data/store.dart';
import 'screens/community_screen.dart';
import 'screens/health_screen.dart';
import 'screens/map_screen.dart';
import 'screens/other_screens.dart';
import 'screens/routes_screen.dart';
import 'widgets/place_sheet.dart' show closePlaceSheet;
import 'theme.dart';
import 'widgets/city_splash.dart';
import 'widgets/pin.dart';
import 'widgets/signup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only the quick local note "has an account" is read before the first frame, so the start
  // picture (or the map) shows at once. Firebase and the saved data load behind it.
  final prefs = await SharedPreferences.getInstance();
  final splash = !(prefs.getBool('hasAccount') ?? false);
  // the city picture of the start screen is read before the first frame
  if (splash) loadStartPicture(); // in the background: the first frame comes at once
  runApp(MobilityApp(splash: splash));
}

Future<AppState> _boot() async {
  await Auth.i.init(); // Firebase sign-in (if this build has the config)
  final state = AppState();
  await state.load();
  await Store.i.load();
  return state;
}

class MobilityApp extends StatelessWidget {
  final bool splash;
  const MobilityApp({super.key, required this.splash});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MOBIlity',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: _Boot(splash: splash),
      );
}

/// Signed in: straight to the working map. Not signed in: the start screen (logo, "Powered by
/// MOBIlity", they part, the city comes in, "Get started"); the map is built behind it. Tapping
/// "Get started" fades it out over the map; 1 second later our sign-in pop-up comes, then the
/// vehicle. The map's guide waits until that is done.
class _Boot extends StatefulWidget {
  final bool splash;
  const _Boot({required this.splash});
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  // first start: the heavy loading (and the map) begins only when the start film is over, so the
  // film never stutters
  final Completer<void> _filmOver = Completer<void>();
  late final Future<AppState> _ready = widget.splash ? _filmOver.future.then((_) => _boot()) : _boot();
  AppState? _state;
  late bool _splash = widget.splash;
  bool _fade = false;
  bool _started = false;
  late bool _loading = !widget.splash; // signed in: the loading logo until the map is on screen

  @override
  void initState() {
    super.initState();
    splashOn.value = _splash;
    startFlow.value = _splash;
    _ready.then((st) {
      if (!mounted) return;
      setState(() => _state = st);
      // the note said "no account", but Firebase knows better (signed in on this phone)
      if (st.hasAccount || !_splash) _end();
    });
  }

  /// "Get started": the start screen fades out over the map, then sign in and the vehicle.
  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final st = await _ready;
    if (!mounted) return;
    setState(() => _fade = true);
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() => _splash = false);
    splashOn.value = false;
    if (st.hasAccount) {
      _end();
      return;
    }
    // the map loads for a moment on its own, then the sign-in pop-up comes over it
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    // over the working map: sign in, then the vehicle (cannot be skipped once signed in)
    final ok = await showSignIn(context, st);
    if (ok && mounted) await showVehicleStep(context, st);
    _end();
  }

  void _end() {
    if (mounted && _splash) setState(() => _splash = false);
    splashOn.value = false;
    startFlow.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return Stack(children: [
      if (st != null) Shell(state: st) else const ColoredBox(color: kStartGrey, child: SizedBox.expand()),
      if (_loading)
        Positioned.fill(
          child: LoadingLogo(
            prepare: () async {
              await _ready; // (the map is put on screen by the listener in initState)
              await WidgetsBinding.instance.endOfFrame;
              await WidgetsBinding.instance.endOfFrame;
            },
            onDone: () {
              if (mounted) setState(() => _loading = false);
            },
          ),
        ),
      if (_splash)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _fade,
            child: AnimatedOpacity(
              opacity: _fade ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Material(
                type: MaterialType.transparency,
                child: CitySplash(
                  onStart: _start,
                  onShown: () {
                    if (!_filmOver.isCompleted) _filmOver.complete();
                  },
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _navKey = GlobalKey();
  int _mapVersion = 0; // rebuilds the map tab (e.g. to replay the guide)
  var _mapKey = GlobalKey<MapScreenState>();

  void _openPlaceOnMap(Place p) {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _mapKey.currentState?.openPlace(p));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MapScreen(key: _mapKey, state: widget.state, navKey: _navKey),
      RoutesScreen(state: widget.state),
      const HealthScreen(),
      CommunityScreen(state: widget.state),
      ProfileScreen(
        state: widget.state,
        onOpenPlace: _openPlaceOnMap,
        onOpenRoutes: () => setState(() => _tab = 1),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        key: _navKey,
        selectedIndex: _tab,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.slateTint,
        onDestinationSelected: (i) => setState(() {
          if (i != _tab) closePlaceSheet(); // the place sheet belongs to the map
          if (i == 0 && _tab != 0 && !widget.state.guideDone) {
            _mapVersion++;
            _mapKey = GlobalKey<MapScreenState>(debugLabel: 'map$_mapVersion');
          }
          _tab = i;
        }),
        destinations: const [
          NavigationDestination(
              icon: MapTabIcon(), selectedIcon: MapTabIcon(color: Color(0xFF2F6FDC)), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Community'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
