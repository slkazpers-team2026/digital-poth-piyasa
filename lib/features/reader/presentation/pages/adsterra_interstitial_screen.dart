import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdsterraInterstitialScreen extends StatefulWidget {
  final String bookId;
  final VoidCallback onAdCompleted;

  const AdsterraInterstitialScreen({
    Key? key,
    required this.bookId,
    required this.onAdCompleted,
  }) : super(key: key);

  @override
  State<AdsterraInterstitialScreen> createState() => _AdsterraInterstitialScreenState();
}

class _AdsterraInterstitialScreenState extends State<AdsterraInterstitialScreen> {
  late final WebViewController _controller;
  int _countdown = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse('https://asiafilm.org/4/3e1b5431f0c1512c95aebc5d7bc7f182'));

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        _timer?.cancel();
        if (mounted) {
          Navigator.of(context).pop();
          widget.onAdCompleted();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent user from closing the ad early via back button
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Loading book in $_countdown...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
