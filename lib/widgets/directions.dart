import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/routing.dart';
import '../theme.dart';

/// The blue route line (white edge so it reads on any map).
PolylineLayer routeLayer(List<LatLng> points) => PolylineLayer(polylines: [
      Polyline(
        points: points,
        strokeWidth: 6,
        color: AppColors.blue,
        borderStrokeWidth: 2,
        borderColor: Colors.white,
      ),
    ]);

IconData stepIcon(String text) {
  final t = text.toLowerCase();
  if (t.startsWith('you have arrived')) return Icons.flag_rounded;
  if (t.contains('slight left') || t.contains('bear left') || t.contains('keep left')) return Icons.turn_slight_left;
  if (t.contains('slight right') || t.contains('bear right') || t.contains('keep right')) return Icons.turn_slight_right;
  if (t.contains('sharp left') || t.contains('turn left')) return Icons.turn_left;
  if (t.contains('sharp right') || t.contains('turn right')) return Icons.turn_right;
  if (t.contains('u-turn')) return Icons.u_turn_left;
  if (t.contains('roundabout')) return Icons.roundabout_right;
  return Icons.straight;
}

/// Turn-by-turn list for a route.
Future<void> showDirections(BuildContext context, RouteResult r, String title) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text('${r.duration} · ${r.distance} · arrive ${r.arrival}',
              style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final s in r.steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE3ECFB),
                child: Icon(stepIcon(s.text), color: AppColors.blue),
              ),
              title: Text(s.text, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: s.meters > 0
                  ? Text(s.meters < 1000 ? '${s.meters.round()} m' : '${(s.meters / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(color: AppColors.soft))
                  : null,
            ),
          const SizedBox(height: 6),
          const Text('Routes © OpenStreetMap contributors · OSRM bike router',
              style: TextStyle(fontSize: 10, color: AppColors.soft)),
        ]),
      ),
    );

/// Card at the bottom of the map while a route is shown.
class RoutePanel extends StatelessWidget {
  final String title;
  final RouteResult? route;
  final bool loading;
  final bool failed;
  final VoidCallback onGo;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  const RoutePanel({
    super.key,
    required this.title,
    required this.route,
    required this.loading,
    required this.failed,
    required this.onGo,
    required this.onClose,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final r = route;
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              if (loading)
                const Text('Finding the best bike route…', style: TextStyle(color: AppColors.soft))
              else if (failed || r == null)
                GestureDetector(
                  onTap: onRetry,
                  child: const Text('No route found · tap to retry',
                      style: TextStyle(color: AppColors.redDark, fontWeight: FontWeight.w700)),
                )
              else
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: r.duration,
                      style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w900, fontSize: 18)),
                  TextSpan(text: '  ${r.distance} · arrive ${r.arrival}', style: const TextStyle(color: AppColors.soft)),
                ])),
            ]),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (r != null)
            FilledButton(
              onPressed: onGo,
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue, minimumSize: const Size(72, 48)),
              child: const Text('GO'),
            ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ]),
      ),
    );
  }
}
