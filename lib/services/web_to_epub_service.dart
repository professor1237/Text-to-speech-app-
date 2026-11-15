import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/block.dart';
import 'web_content_parser.dart';

typedef WebViewHtmlFallback = Future<String> Function();

class ExtractedWebPage {
  final String title;
  final String author;
  final String sourceUrl;
  final List<Block> blocks;
  final String method;
  const ExtractedWebPage({
    required this.title,
    required this.author,
    required this.sourceUrl,
    required this.blocks,
    required this.method,
  });
}

/// HTTP-first extraction with the active, authenticated WebView as fallback.
class WebToEpubService {
  WebToEpubService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<ExtractedWebPage> extractCurrentPage({
    required String url,
    required String pageTitle,
    required WebViewHtmlFallback webViewFallback,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw Exception('Only HTTP and HTTPS pages can be converted.');
    }
    var blocks = <Block>[];
    var method = 'HTTP';
    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 18));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        blocks = WebContentParser.parse(_decode(response));
      }
    } catch (_) {
      // The currently open WebView may have a logged-in session or rendered DOM.
    }
    if (_usable(blocks)) return _result(url, pageTitle, blocks, method);

    method = 'WebView';
    try {
      final html = await webViewFallback().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception('WebView extraction timed out.'),
      );
      blocks = WebContentParser.parse(html);
    } catch (e) {
      throw Exception('HTTP and WebView extraction both failed: $e');
    }
    if (!_usable(blocks)) {
      throw Exception('No reliable chapter text was found on this page.');
    }
    return _result(url, pageTitle, blocks, method);
  }

  ExtractedWebPage _result(String url, String pageTitle, List<Block> blocks, String method) {
    final uri = Uri.parse(url);
    return ExtractedWebPage(
      title: pageTitle.trim().isEmpty ? uri.host : pageTitle.trim(),
      author: uri.host,
      sourceUrl: url,
      blocks: blocks,
      method: method,
    );
  }

  bool _usable(List<Block> blocks) {
    final count = blocks.fold<int>(0, (sum, b) => sum + b.text.length);
    return blocks.length >= 2 && count >= 120;
  }

  String _decode(http.Response response) {
    final type = response.headers['content-type'] ?? '';
    final charset = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
        .firstMatch(type)?.group(1)?.replaceAll('"', '').replaceAll("'", '');
    if (charset?.toLowerCase() == 'iso-8859-1') {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  void close() => _client.close();
}