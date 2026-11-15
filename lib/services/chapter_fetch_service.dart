import 'package:http/http.dart' as http;
import '../models/block.dart';
import 'web_epub_settings_service.dart';
import 'web_content_parser.dart';

typedef ChapterWebViewFallback = Future<String> Function(Uri uri);

class ChapterFetchResult {
  const ChapterFetchResult({required this.blocks, required this.method});
  final List<Block> blocks;
  final String method;
}

/// Fetches a chapter over HTTP first, then falls back to a rendered WebView.
class ChapterFetchService {
  ChapterFetchService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<ChapterFetchResult> fetch(
    Uri uri, {
    required ChapterWebViewFallback webViewFallback,
    int retries = 0,
  }) async {
    final profile = WebEpubSettingsService.forUri(uri);
    final attempts = retries.clamp(0, 5) + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _client.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 18));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final blocks = WebContentParser.parse(response.body);
          if (_usable(blocks)) return ChapterFetchResult(blocks: blocks, method: 'HTTP');
        }
      } catch (_) {
        // Retry HTTP before falling back to the site's rendered session.
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(Duration(seconds: profile.delaySeconds > 0 ? profile.delaySeconds : 1));
      }
    }

    final html = await webViewFallback(uri).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('WebView extraction timed out.'),
    );
    final blocks = WebContentParser.parse(html);
    if (!_usable(blocks)) throw Exception('The page did not contain enough readable chapter text.');
    return ChapterFetchResult(blocks: blocks, method: 'WebView');
  }

  bool _usable(List<Block> blocks) =>
      blocks.length >= 2 && blocks.fold<int>(0, (n, b) => n + b.text.length) >= 100;

  void close() => _client.close();
}