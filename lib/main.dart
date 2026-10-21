import 'package:flutter/material.dart';

import 'data/app_state.dart';
import 'screens/community_screen.dart';
import 'screens/health_screen.dart';
import 'screens/map_screen.dart';
import 'screens/other_screens.dart';
import 'screens/routes_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
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
        home: Shell(state: state),
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      MapScreen(key: ValueKey(_mapVersion), state: widget.state, navKey: _navKey),
      const RoutesScreen(),
      const HealthScreen(),
      CommunityScreen(state: widget.state),
      ProfileScreen(state: widget.state),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        key: _navKey,
        selectedIndex: _tab,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.slateTint,
        onDestinationSelected: (i) => setState(() {
          if (i == 0 && _tab != 0 && !widget.state.guideDone) _mapVersion++;
          _tab = i;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Community'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
