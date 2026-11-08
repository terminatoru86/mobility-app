import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player/video_player.dart';

import '../data/places.dart' show userPos;

/// The start screen (2–3 s while the app loads behind it): a drone video of the rider's city,
/// "Powered by MOBIlity" with the logo in the bottom-left corner. Then it fades away.
///
/// Videos: assets/splash/<city>.mp4 (see assets/splash/README.md). The city is the nearest one
/// that has a video, within 60 km of the last known position; otherwise a calm dark background.
const kSplashCities = <String, LatLng>{
  'chicago': LatLng(41.8781, -87.6298),
};

class CitySplash extends StatefulWidget {
  final Duration show;
  const CitySplash({super.key, this.show = const Duration(milliseconds: 2600)});
  @override
  State<CitySplash> createState() => _CitySplashState();
}

class _CitySplashState extends State<CitySplash> {
  VideoPlayerController? _video;
  bool _fading = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _start();
    Timer(widget.show, () {
      if (mounted) setState(() => _fading = true);
    });
  }

  Future<void> _start() async {
    const d = Distance();
    String? best;
    double bestKm = 60;
    for (final e in kSplashCities.entries) {
      final km = d(userPos, e.value) / 1000;
      if (km < bestKm) {
        bestKm = km;
        best = e.key;
      }
    }
    if (best == null) return;
    final asset = 'assets/splash/$best.mp4';
    try {
      await rootBundle.load(asset); // only if the video is in the app
      final c = VideoPlayerController.asset(asset, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (!mounted) return c.dispose();
      setState(() => _video = c);
    } catch (_) {
      // no video for this city yet: the dark background stays
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final v = _video;
    return IgnorePointer(
      ignoring: _fading,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: const Duration(milliseconds: 450),
        onEnd: () {
          if (_fading && mounted) {
            _video?.pause();
            setState(() => _gone = true);
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1B2A35), Color(0xFF0E161C)],
              ),
            ),
          ),
          if (v != null && v.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
            ),
          // a soft dark fade at the bottom so the text reads on any video
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.55, 1],
                colors: [Color(0x00000000), Color(0x99000000)],
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                child: SvgPicture.asset('assets/brand/logo_m.svg'),
              ),
              const SizedBox(width: 10),
              const Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Powered by ', style: TextStyle(fontWeight: FontWeight.w500)),
                  TextSpan(text: 'MOBIlity', style: TextStyle(fontWeight: FontWeight.w900)),
                ]),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  shadows: [Shadow(color: Color(0x80000000), blurRadius: 6)],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
