import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Phone: the page opens inside the app in a web view.
class WebFrame extends StatefulWidget {
  final Uri url;
  const WebFrame(this.url, {super.key});
  @override
  State<WebFrame> createState() => _WebFrameState();
}

class _WebFrameState extends State<WebFrame> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(widget.url);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}
