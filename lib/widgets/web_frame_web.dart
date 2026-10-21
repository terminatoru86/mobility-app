import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Browser build: the page opens inside the app in a frame.
class WebFrame extends StatefulWidget {
  final Uri url;
  const WebFrame(this.url, {super.key});
  @override
  State<WebFrame> createState() => _WebFrameState();
}

class _WebFrameState extends State<WebFrame> {
  static int _n = 0;
  late final String _id = 'fixit-frame-${_n++}';

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_id, (int _) {
      final f = web.HTMLIFrameElement()
        ..src = widget.url.toString()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return f;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _id);
}
