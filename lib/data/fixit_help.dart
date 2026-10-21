import 'package:shared_preferences/shared_preferences.dart';

/// Help pages for self-service repair stands ("fix it yourself").
///
/// The QR code on a stand is the best source: it opens the maker's own
/// instructions. When a rider scans one, we remember the link for that maker,
/// so the next stand of the same maker opens its guide without scanning.
class FixitGuide {
  final String maker; // shown to the rider
  final String url;
  const FixitGuide(this.maker, this.url);
}

/// Known makers -> their help page. Anything else falls back to the
/// Park Tool repair guides (free, step by step, for every common repair).
const _known = <String, FixitGuide>{
  'dero': FixitGuide('Dero Fixit', 'https://www.dero.com/topics/dero-fixit/'),
};
const kGeneralGuide = FixitGuide('Park Tool repair help', 'https://www.parktool.com/en-us/blog/repair-help');

String _key(String? brand) {
  final b = (brand ?? '').toLowerCase();
  for (final k in const ['dero', 'saris', 'huntco', 'cyclesafe', 'belson', 'fixtation', 'sportworks', 'park tool', 'ibike']) {
    if (b.contains(k)) return k.replaceAll(' ', '');
  }
  return b.trim();
}

/// The guide for a stand: a link scanned before for this maker, else the maker's page, else the general guide.
Future<FixitGuide> guideFor(String? brand) async {
  final k = _key(brand);
  if (k.isNotEmpty) {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString('fixit_$k');
      if (saved != null) return FixitGuide(_title(brand), saved);
    } catch (_) {}
    final known = _known[k];
    if (known != null) return known;
  }
  return kGeneralGuide;
}

String _title(String? brand) {
  final b = (brand ?? '').trim();
  return b.isEmpty ? 'Repair help' : '${b[0].toUpperCase()}${b.substring(1)} help';
}

/// A scanned QR value we are willing to open: only web links.
Uri? helpLink(String? raw) {
  final s = (raw ?? '').trim();
  final u = Uri.tryParse(s.startsWith('www.') ? 'https://$s' : s);
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return null;
  return u;
}

/// Remember the scanned link for this maker (only when we know the maker).
Future<void> rememberScan(String? brand, Uri link) async {
  final k = _key(brand);
  if (k.isEmpty) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('fixit_$k', link.toString());
  } catch (_) {}
}
