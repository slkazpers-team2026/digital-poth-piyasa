import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdsterraBanner extends StatefulWidget {
  final double height;
  const AdsterraBanner({Key? key, this.height = 60}) : super(key: key);

  @override
  State<AdsterraBanner> createState() => _AdsterraBannerState();
}

class _AdsterraBannerState extends State<AdsterraBanner> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..loadRequest(Uri.parse('https://asiafilm.org/4/2b6cc6af4c46295243d17a590353aef7'));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: WebViewWidget(controller: _controller),
    );
  }
}
