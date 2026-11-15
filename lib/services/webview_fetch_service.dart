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
  Future<void> _queue = Future<void>.value();

  Future<String> fetch(Uri uri) {
    final result = _queue.then((_) => _fetchOne(uri));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> _fetchOne(Uri uri) async {
    _pending = Completer<void>();
    await controller.loadRequest(uri);
    await _pending!.future.timeout(const Duration(seconds: 25));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final raw = await controller.runJavaScriptReturningResult(
      'document.documentElement ? document.documentElement.outerHTML : ""',
    );
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