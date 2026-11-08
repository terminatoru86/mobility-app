import 'package:flutter/material.dart';

import 'data/app_state.dart';
import 'data/places.dart';
import 'data/store.dart';
import 'screens/community_screen.dart';
import 'screens/health_screen.dart';
import 'screens/map_screen.dart';
import 'screens/other_screens.dart';
import 'screens/routes_screen.dart';
import 'theme.dart';
import 'widgets/city_splash.dart';
import 'widgets/pin.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  await Store.i.load();
  runApp(MobilityApp(state: state));
}

class MobilityApp extends StatelessWidget {
  final AppState state;
  const MobilityApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MOBIlity',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // the app starts loading right away; the city video sits on top for 2–3 s, then fades
        home: Stack(children: [
          Shell(state: state),
          const Positioned.fill(child: Material(type: MaterialType.transparency, child: CitySplash())),
        ]),
      );
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
