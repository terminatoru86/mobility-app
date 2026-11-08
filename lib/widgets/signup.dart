import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_state.dart';
import '../data/places.dart';
import '../theme.dart';

/// Account invite (variant A): small card in the middle.
/// Only Apple or Google. "Skip" closes it.
Future<void> showSignupInvite(BuildContext context, AppState state) async {
  final created = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x660F1E24),
    builder: (_) => const _InviteCard(),
  );
  if (created == true && context.mounted) {
    // Real Apple / Google sign-in comes with Firebase (M2). For now we mark the account as created.
    await state.createAccount();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierColor: const Color(0x660F1E24),
        builder: (_) => _VehicleStep(state: state),
      );
    }
  }
}

/// After signing in from the start screen: which vehicle do you ride?
Future<void> showVehicleStep(BuildContext context, AppState state) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x660F1E24),
      builder: (_) => _VehicleStep(state: state),
    );

class _Card extends StatelessWidget {
  final Widget badge;
  final List<Widget> children;
  const _Card({required this.badge, required this.children});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          margin: const EdgeInsets.only(top: 28),
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x2A0F1E24), blurRadius: 14, offset: Offset(0, 5))],
          ),
          alignment: Alignment.center,
          child: badge,
        ),
      ]),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard();

  @override
  Widget build(BuildContext context) {
    Widget benefit(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        );
    return _Card(
      badge: SvgPicture.asset('assets/brand/logo_m.svg', width: 40, height: 40),
      children: [
        const Text('Save your rides', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Your places, routes and vehicle on any phone.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.soft)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          benefit(Icons.favorite, 'Places'),
          benefit(Icons.route, 'Routes'),
          benefit(Icons.pedal_bike, 'Vehicle'),
        ]),
        const SizedBox(height: 14),
        _ssoButton('Continue with Apple', Colors.black, Colors.white, () => Navigator.pop(context, true)),
        const SizedBox(height: 8),
        _ssoButton('Continue with Google', Colors.white, AppColors.ink, () => Navigator.pop(context, true),
            border: true),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
        ),
      ],
    );
  }

  Widget _ssoButton(String t, Color bg, Color fg, VoidCallback onTap, {bool border = false}) => SizedBox(
        width: double.infinity,
        height: 46,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            shape: StadiumBorder(side: border ? const BorderSide(color: AppColors.line, width: 1.5) : BorderSide.none),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          child: Text(t),
        ),
      );
}

/// Step 2: which vehicle do you ride? One big vehicle at a time,
/// it changes by itself every 3 s; swipe left/right or tap the arrows, then choose.
class _VehicleStep extends StatefulWidget {
  final AppState state;
  const _VehicleStep({required this.state});
  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  static const _vehicles = [Vehicle.bike, Vehicle.scooter, Vehicle.moped, Vehicle.moto];
  final _pc = PageController();
  final _model = TextEditingController();
  Timer? _t;
  int _i = 0;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_touched && _pc.hasClients) {
        _pc.animateToPage((_i + 1) % _vehicles.length,
            duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _pc.dispose();
    _model.dispose();
    super.dispose();
  }

  void _go(int d) {
    _touched = true;
    _pc.animateToPage((_i + d) % _vehicles.length, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final v = _vehicles[_i];
    return _Card(
      badge: const Icon(Icons.check_rounded, color: AppColors.greenDark, size: 30),
      children: [
        const Text('What do you ride?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Vehicles change by themselves. Swipe left or right and pick yours.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.soft)),
        const SizedBox(height: 12),
        Container(
          height: 120,
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(18)),
          child: Stack(alignment: Alignment.center, children: [
            Listener(
              onPointerDown: (_) => _touched = true,
              child: PageView.builder(
                controller: _pc,
                itemCount: _vehicles.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (_, i) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(height: 70, child: Image.asset(_vehicles[i].asset, fit: BoxFit.contain)),
                  const SizedBox(height: 6),
                  Text(_vehicles[i].label, style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            Positioned(left: 4, child: _arrow(Icons.chevron_left, () => _go(-1))),
            Positioned(right: 4, child: _arrow(Icons.chevron_right, () => _go(1))),
          ]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _vehicles.length,
            (k) => Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: k == _i ? AppColors.primary : const Color(0xFFC9D1D5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _model,
          decoration: const InputDecoration(
            hintText: 'Model, e.g. Trek FX 2',
            isDense: true,
            filled: true,
            fillColor: AppColors.paper,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            await widget.state.saveVehicle(v, _model.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: Text('Choose ${v.label.toLowerCase()}'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.slate)),
        ),
      ],
    );
  }

  Widget _arrow(IconData i, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, color: AppColors.primary)),
        ),
      );
}
