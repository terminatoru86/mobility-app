import 'dart:async';

import 'package:flutter/material.dart';

import '../data/places.dart';
import '../data/weather.dart';
import '../theme.dart';
import 'glass.dart';

/// The colour of the weather: our red for rain, our yellow for drizzle, our green for clear
/// sky, our blue for clouds (and while the weather is still loading).
StatusColors weatherColors(Weather? wx) => switch (wx?.tone) {
      'rain' => colorsFor(Status.full),
      'drizzle' => colorsFor(Status.almost),
      'clear' => colorsFor(Status.free),
      _ => const StatusColors(AppColors.blue, Color(0xFFE6EEFB), Color(0xFF1F4FA8)),
    };

IconData weatherIcon(Weather? wx) => switch (wx?.sky ?? 'Cloudy') {
      'Clear' => Icons.wb_sunny_outlined,
      'Rain' || 'Showers' => Icons.umbrella_outlined,
      'Snow' => Icons.ac_unit,
      'Storm' => Icons.thunderstorm_outlined,
      _ => Icons.wb_cloudy_outlined,
    };

/// The round glass button next to the search bar (and on the walking screen): your vehicle on one
/// side, the weather on the other. It turns by itself every 8 s; a swipe left or right turns it
/// at once. The weather side takes the colour of the weather; a blue dot says rain is coming.
class WxVehicleButton extends StatefulWidget {
  final Weather? wx;
  final Vehicle vehicle;
  final VoidCallback? onVehicle, onWeather;
  const WxVehicleButton({super.key, required this.wx, required this.vehicle, this.onVehicle, this.onWeather});

  @override
  State<WxVehicleButton> createState() => _WxVehicleButtonState();
}

class _WxVehicleButtonState extends State<WxVehicleButton> {
  bool _weather = false;
  Timer? _turn;

  void _restart() {
    _turn?.cancel();
    _turn = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => _weather = !_weather);
    });
  }

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _turn?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wc = weatherColors(widget.wx);
    return GestureDetector(
      onTap: _weather ? widget.onWeather : widget.onVehicle,
      onHorizontalDragEnd: (_) {
        setState(() => _weather = !_weather);
        _restart(); // the next turn by itself comes a full 8 s after the swipe
      },
      child: Stack(clipBehavior: Clip.none, children: [
        Glass(
          width: kCtl,
          height: kCtl,
          color: _weather ? wc.tint.withValues(alpha: 0.55) : kGlass,
          line: _weather ? wc.main : kGlassLine,
          lineWidth: _weather ? 1.5 : 0.6,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: _weather
                ? Column(key: const ValueKey(true), mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(weatherIcon(widget.wx), size: 19, color: wc.dark),
                    Text(widget.wx == null ? '--°' : '${widget.wx!.temp.round()}°',
                        style: TextStyle(fontSize: 12, height: 1.05, fontWeight: FontWeight.w800, color: wc.dark)),
                  ])
                : Padding(
                    key: const ValueKey(false),
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(widget.vehicle.asset),
                  ),
          ),
        ),
        if (widget.wx?.rainInMinutes != null)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: AppColors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            ),
          ),
      ]),
    );
  }
}
