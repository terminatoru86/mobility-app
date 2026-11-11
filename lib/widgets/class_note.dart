import 'package:flutter/material.dart';

import '../data/ride_classes.dart';
import '../theme.dart';
import 'place_sheet.dart' show openLink;

/// Our note about a learn-to-ride program: a few lines to read, then the link to the people who run it.
Future<void> showClassNote(BuildContext context, RideClass c) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x380F1E24),
      builder: (_) => _ClassNote(c),
    );

class _ClassNote extends StatelessWidget {
  final RideClass c;
  const _ClassNote(this.c);

  @override
  Widget build(BuildContext context) {
    final national = identical(c, kNationalClass);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ClassBadge(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(c.who, style: const TextStyle(fontSize: 12.5, color: AppColors.soft)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Text(c.note, style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text('Dates and sign-up are on their page.', style: TextStyle(fontSize: 12, color: AppColors.soft)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openLink(c.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(national ? 'Open All Kids Bike' : 'Open the program'),
            ),
            if (!national) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => openLink(kNationalClass.url),
                  child: const Text('In schools nationwide: All Kids Bike ›'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The sign of a kids' class: a child's bike on our blue.
class ClassBadge extends StatelessWidget {
  final double size;
  const ClassBadge({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: Icon(Icons.child_care_rounded, size: size * 0.56, color: Colors.white),
      );
}

/// A low white pill with the badge and one line: tap to read the note.
class ClassPill extends StatelessWidget {
  final RideClass c;
  const ClassPill(this.c, {super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showClassNote(context, c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const ClassBadge(size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.soft),
          ]),
        ),
      );
}
