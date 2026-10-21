import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/cameras.dart';
import '../screens/fixit_screens.dart' show HelpPageScreen;
import '../theme.dart';
import 'web_frame_stub.dart' if (dart.library.js_interop) 'web_frame_web.dart';

/// Live view from the nearest public traffic camera (refreshed every minute).
/// It shows the street around the parking, not the rack itself.
class CameraCard extends StatefulWidget {
  final TrafficCamera cam;
  const CameraCard(this.cam, {super.key});
  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  Timer? _t;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 60), (_) => setState(() => _n++));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Uri get _url {
    final u = Uri.parse(widget.cam.image);
    if (_n == 0) return u;
    // ask for a fresh picture (no old copy from the cache)
    return u.replace(queryParameters: {...u.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch ~/ 60000}'});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cam;
    final m = c.meters < 1000 ? '${(c.meters / 10).round() * 10} m' : '${(c.meters / 1000).toStringAsFixed(1)} km';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        const Text('Live camera nearby', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.soft)),
        const Spacer(),
        Text('$m · ${c.source}', style: const TextStyle(fontSize: 11, color: AppColors.soft)),
      ]),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HelpPageScreen(url: _url, title: c.name.isEmpty ? 'Traffic camera' : c.name),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: AppColors.paper),
              // the browser build shows the picture in a frame (camera servers do not allow it otherwise)
              if (kIsWeb)
                AbsorbPointer(child: WebFrame(_url, key: ValueKey(_n)))
              else
                Image.network(
                  _url.toString(),
                  key: ValueKey(_n),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Camera offline', style: TextStyle(color: AppColors.soft, fontSize: 12)),
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                right: 8,
                child: Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Text('Public traffic camera: it shows the street around, not the rack itself. New picture every minute.',
          style: TextStyle(fontSize: 10.5, color: AppColors.soft)),
    ]);
  }
}
