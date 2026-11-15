import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewFetchService {
  WebViewFetchService() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          if (url == 'about:blank') return;
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

  static const _loadTimeout = Duration(seconds: 25);
  static const _scriptTimeout = Duration(seconds: 10);

  late final WebViewController controller;
  Completer<void>? _pending;
  Future<void> _queue = Future<void>.value();

  Future<String> fetch(Uri uri) {
    final result = _queue.then((_) => _fetchOne(uri));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> _fetchOne(Uri uri) async {
    final pending = Completer<void>();
    _pending = pending;
    try {
      final loaded = pending.future.timeout(_loadTimeout);
      loaded.ignore();
      await controller.loadRequest(uri);
      await loaded;
      await _waitForRenderedText();
      final raw = await controller
          .runJavaScriptReturningResult(
            'document.documentElement ? document.documentElement.outerHTML : ""',
          )
          .timeout(_scriptTimeout);
      return _decodeJsResult(raw);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _waitForRenderedText() async {
    var previous = -1;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final raw = await controller
          .runJavaScriptReturningResult(
            'document.body ? document.body.innerText.length : 0',
          )
          .timeout(_scriptTimeout);
      final length = int.tryParse(raw.toString().replaceAll('"', '').trim()) ?? 0;
      if (length > 200 && length == previous) return;
      previous = length;
    }
  }

  String _decodeJsResult(Object raw) {
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