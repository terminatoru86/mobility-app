import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../theme.dart';

/// Tabs that come in the next milestones (M2-M6).
class ComingSoon extends StatelessWidget {
  final String title;
  final String text;
  final IconData icon;
  const ComingSoon({super.key, required this.title, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            Center(child: Icon(icon, size: 64, color: AppColors.slate)),
            const SizedBox(height: 12),
            Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.soft))),
          ]),
        ),
      );
}

class ProfileScreen extends StatelessWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            SvgPicture.asset('assets/brand/logo_m.svg', width: 36, height: 36),
            const SizedBox(width: 8),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'MOBI', style: TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(text: 'lity', style: TextStyle(fontWeight: FontWeight.w400)),
            ]), style: TextStyle(fontSize: 26)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.hasAccount ? 'Your account' : 'Guest',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(state.myVehicle == null
                      ? 'No vehicle saved'
                      : '${state.myVehicle!.label}${state.model.isEmpty ? '' : ' · ${state.model}'}',
                      style: const TextStyle(color: AppColors.soft)),
                ]),
              ),
              if (state.myVehicle != null)
                SizedBox(width: 64, height: 50, child: Image.asset(state.myVehicle!.asset)),
            ]),
          ),
          const SizedBox(height: 16),
          _item(Icons.favorite_border, 'Saved places'),
          _item(Icons.route, 'Saved routes'),
          _item(Icons.layers_outlined, 'What appears on the map'),
          _item(Icons.sync_alt, 'Sharing operators'),
          _item(Icons.notifications_none, 'Notifications'),
          _item(Icons.shield_outlined, 'Anti-theft & insurance'),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Help · Replay the guide'),
            subtitle: state.guideDone ? null : const Text('Starts when you open the Map tab'),
            onTap: state.replayGuide,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset demo (start as a new user)'),
            subtitle: Text('App opens counted: ${state.opens}'),
            onTap: state.resetDemo,
          ),
        ]),
      ),
    );
  }

  Widget _item(IconData i, String t) => ListTile(
        leading: Icon(i),
        title: Text(t),
        trailing: const Icon(Icons.chevron_right),
      );
}
