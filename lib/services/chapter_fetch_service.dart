import 'package:http/http.dart' as http;
import '../models/block.dart';
import 'http_decode.dart';
import 'web_content_parser.dart';

typedef ChapterWebViewFallback = Future<String> Function(Uri uri);

class ChapterFetchResult {
  const ChapterFetchResult({required this.blocks, required this.method});
  final List<Block> blocks;
  final String method;
}

class ChapterFetchService {
  ChapterFetchService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<ChapterFetchResult> fetch(
    Uri uri, {
    required ChapterWebViewFallback webViewFallback,
    int retries = 0,
  }) async {
    final attempts = retries.clamp(0, 5).toInt() + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      var retryable = true;
      try {
        final response = await _client.get(uri, headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        }).timeout(const Duration(seconds: 18));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final blocks = WebContentParser.parse(decodeHtmlResponse(response));
          if (_usable(blocks)) return ChapterFetchResult(blocks: blocks, method: 'HTTP');
          retryable = false; // script-rendered page: go to WebView
        } else {
          retryable = _isTransient(response.statusCode);
        }
      } catch (_) {}
      if (!retryable) break;
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }

    // No outer timeout: the WebView service has its own per-page timeouts,
    // and an outer one would also count time spent waiting in the queue.
    final html = await webViewFallback(uri);
    final blocks = WebContentParser.parse(html);
    if (!_usable(blocks)) throw Exception('The page did not contain enough readable chapter text.');
    return ChapterFetchResult(blocks: blocks, method: 'WebView');
  }

  bool _isTransient(int status) =>
      status == 408 || status == 425 || status == 429 || status >= 500;

  bool _usable(List<Block> blocks) =>
      blocks.length >= 2 && blocks.fold<int>(0, (n, b) => n + b.text.length) >= 100;

  void close() => _client.close();
}