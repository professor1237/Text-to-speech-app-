import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

/// Owns an isolated WebView controller so chapter fallback does not navigate
/// or replace the user's active browser tab.
class WebViewFetchService {
  WebViewFetchService() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          final pending = _pending;
          if (pending != null && !pending.isCompleted) pending.complete();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            final pending = _pending;
            if (pending != null && !pending.isCompleted) {
              pending.completeError(Exception(error.description));
            }
          }
        },
      ));
  }

  late final WebViewController controller;
  Completer<void>? _pending;

  Future<String> fetch(Uri uri) async {
    _pending = Completer<void>();
    await controller.loadRequest(uri);
    await _pending!.future.timeout(const Duration(seconds: 25));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final raw = await controller.runJavaScriptReturningResult(
      'document.documentElement ? document.documentElement.outerHTML : ""',
    );
    // Android returns the JS result JSON-encoded, so decode it.
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is String ? decoded : raw;
      } catch (_) {
        return raw;
      }
    }
    return raw.toString();
  }
}