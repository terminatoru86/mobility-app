import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/fixit_help.dart';
import '../theme.dart';
import '../widgets/web_frame_stub.dart' if (dart.library.js_interop) '../widgets/web_frame_web.dart';

/// "Fixit help": the camera reads the QR code on the stand,
/// then the maker's instructions open inside the app.
class FixitScanScreen extends StatefulWidget {
  final String? brand;
  const FixitScanScreen({super.key, this.brand});
  @override
  State<FixitScanScreen> createState() => _FixitScanScreenState();
}

class _FixitScanScreenState extends State<FixitScanScreen> {
  final _cam = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _notLink; // a QR that is not a web link

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  Future<void> _open(Uri url, String title) async {
    _done = true;
    await _cam.stop();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HelpPageScreen(url: url, title: title)),
    );
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final link = helpLink(b.rawValue);
      if (link != null) {
        rememberScan(widget.brand, link);
        _open(link, link.host.replaceFirst('www.', ''));
        return;
      }
      if ((b.rawValue ?? '').isNotEmpty) setState(() => _notLink = b.rawValue);
    }
  }

  Future<void> _noQr() async {
    final g = await guideFor(widget.brand);
    if (mounted) _open(Uri.parse(g.url), g.maker);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _cam,
            onDetect: _onDetect,
            errorBuilder: (_, __, ___) => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Camera is not available.\nAllow the camera, or open the guide below.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
              ),
            ),
          ),
        ),
        // frame to aim at the QR sticker
        Center(
          child: Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const Expanded(
                child: Text('Scan the QR on the stand',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: () => _cam.toggleTorch(),
                icon: const Icon(Icons.flashlight_on_outlined, color: Colors.white),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 28,
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_notLink != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('This code is not a help link:\n$_notLink',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _noQr,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('No QR? Open the repair guide'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The maker's help page, kept inside the app.
class HelpPageScreen extends StatelessWidget {
  final Uri url;
  final String title;
  const HelpPageScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text(url.host, style: const TextStyle(fontSize: 11, color: AppColors.soft)),
        ]),
        actions: [
          // some sites refuse to show inside other apps: open them in the browser
          IconButton(
            tooltip: 'Open in browser',
            onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: WebFrame(url),
    );
  }
}
