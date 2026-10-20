import 'package:flutter/material.dart';

import '../data/places.dart';
import '../theme.dart';
import 'pin.dart';

class GuideStep {
  final GlobalKey? target; // null = no spotlight (centered note)
  final String title;
  final String text;
  final Widget? extra;
  const GuideStep(this.target, this.title, this.text, {this.extra});
}

/// After-install guide: dims the screen, spotlights one control at a time
/// and shows a note next to it, like a notification. "Skip" closes it.
class GuideOverlay extends StatefulWidget {
  final List<GuideStep> steps;
  final int total; // includes the sheet step shown later
  final VoidCallback onFinish;
  const GuideOverlay({super.key, required this.steps, required this.total, required this.onFinish});

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay> {
  int _i = 0;

  Rect? _rectOf(GlobalKey? k) {
    final ctx = k?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final o = box.localToGlobal(Offset.zero);
    return (o & box.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final size = MediaQuery.of(context).size;
    final r = _rectOf(step.target);
    final below = r == null || r.center.dy < size.height * 0.5;
    final last = _i == widget.steps.length - 1;

    final tip = Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.green, width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_i + 1} OF ${widget.total}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.greenDark)),
          const SizedBox(height: 2),
          Text(step.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(step.text, style: const TextStyle(fontSize: 12.5, color: AppColors.soft)),
          if (step.extra != null) ...[const SizedBox(height: 8), step.extra!],
          Row(children: [
            ...List.generate(
              widget.total,
              (k) => Container(
                width: k == _i ? 12 : 5,
                height: 5,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: k == _i ? AppColors.green : const Color(0xFFC9D1D5),
                ),
              ),
            ),
            const Spacer(),
            TextButton(onPressed: widget.onFinish, child: const Text('Skip')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 36)),
              onPressed: () => last ? widget.onFinish() : setState(() => _i++),
              child: const Text('Next'),
            ),
          ]),
        ]),
      ),
    );

    double top;
    if (r == null) {
      top = size.height * 0.3;
    } else if (below) {
      top = r.bottom + 10;
    } else {
      top = r.top - 10 - 210;
    }

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () {},
          child: CustomPaint(painter: _ScrimPainter(r)),
        ),
      ),
      Positioned(left: (size.width - 280) / 2, top: top.clamp(40, size.height - 260), child: tip),
    ]);
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  _ScrimPainter(this.hole);
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final paint = Paint()..color = const Color(0xA60F1E24);
    if (hole == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final h = Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(24)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, h), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!, const Radius.circular(24)),
      Paint()
        ..color = AppColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole;
}

/// Mini legend shown in step 3 (how to read pins).
class MiniLegend extends StatelessWidget {
  const MiniLegend({super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(Status s, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: colorsFor(s).tint,
                shape: BoxShape.circle,
                border: Border.all(color: colorsFor(s).main, width: 2),
              ),
            ),
            const SizedBox(width: 8),
            Text(t, style: const TextStyle(fontSize: 12)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row(Status.free, 'free · the number = spots left'),
      row(Status.almost, 'almost full'),
      row(Status.full, 'full or broken (no number)'),
      row(Status.unknown, 'no update for 4 h'),
      Row(children: [
        const Glyph(PlaceType.service, size: 14, color: AppColors.slate),
        const SizedBox(width: 8),
        const Text('service, shop, rent… with rating', style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }
}
