import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../models/web_chapter.dart';

/// Discovers likely chapter links from a table-of-contents page.
class ChapterDiscoveryService {
  ChapterDiscoveryService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static final _chapterHint = RegExp(
    r'(chapter|episode|part|volume|prologue|epilogue|第[0-9一二三四五六七八九十百]+章)',
    caseSensitive: false,
  );
  static final _urlHint = RegExp(
    r'/(chapter|chap|episode|ep|part|volume|read|novel)/|[-_/](\d{1,5})(?:\.html?)?$',
    caseSensitive: false,
  );

  Future<List<WebChapter>> discover(String sourceUrl, {int maxChapters = 500}) async {
    final start = Uri.parse(sourceUrl);
    if (!{'http', 'https'}.contains(start.scheme)) {
      throw Exception('Use a valid HTTP or HTTPS table-of-contents URL.');
    }
    final visitedPages = <String>{};
    final found = <String, WebChapter>{};
    final pages = <Uri>[start];

    // Follow a small number of explicit pagination links, not arbitrary site links.
    while (pages.isNotEmpty && visitedPages.length < 8 && found.length < maxChapters) {
      final page = pages.removeAt(0);
      if (!visitedPages.add(page.toString())) continue;
      final response = await _client.get(page, headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 18));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (page == start) throw Exception('Could not load the table of contents (HTTP ${response.statusCode}).');
        continue;
      }
      final document = html_parser.parse(response.body);
      final root = document.querySelector('article, main, [role="main"], .toc, .chapter-list, .list-chapter') ??
          document.body ?? document.documentElement;
      if (root == null) continue;

      for (final anchor in root.querySelectorAll('a[href]')) {
        if (found.length >= maxChapters) break;
        final href = anchor.attributes['href'];
        final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (href == null || label.length < 2) continue;
        final uri = page.resolve(href);
        if (!{'http', 'https'}.contains(uri.scheme) || uri.host != start.host) continue;
        if (uri.path == page.path && uri.query == page.query) continue;
        if (_isPagination(label, anchor.attributes['rel'] ?? '')) {
          if (pages.length < 7 && !visitedPages.contains(uri.toString())) pages.add(uri);
          continue;
        }
        if (!_looksLikeChapter(label, uri)) continue;
        found.putIfAbsent(uri.toString(), () => WebChapter(
          title: label,
          url: uri.toString(),
          order: found.length,
        ));
      }
    }
    if (found.isEmpty) {
      throw Exception('No chapter links were detected. This website may need a site-specific adapter or manual chapter URLs.');
    }
    return found.values.toList();
  }


  /// Parses a JavaScript-rendered TOC already loaded in the user's browser.
  List<WebChapter> discoverFromHtml(String html, String sourceUrl, {int maxChapters = 500}) {
    final start = Uri.parse(sourceUrl);
    final document = html_parser.parse(html);
    final root = document.querySelector('article, main, [role="main"], .toc, .chapter-list, .list-chapter') ??
        document.body ?? document.documentElement;
    if (root == null) return [];
    final found = <String, WebChapter>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      if (found.length >= maxChapters) break;
      final href = anchor.attributes['href'];
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (href == null || label.length < 2) continue;
      final uri = start.resolve(href);
      if (!{'http', 'https'}.contains(uri.scheme) || uri.host != start.host) continue;
      if (!_looksLikeChapter(label, uri)) continue;
      found.putIfAbsent(uri.toString(), () => WebChapter(
        title: label, url: uri.toString(), order: found.length,
      ));
    }
    return found.values.toList();
  }

  bool _looksLikeChapter(String label, Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.png') || path.endsWith('.css') ||
        path.endsWith('.js') || path.endsWith('.pdf')) return false;
    return _chapterHint.hasMatch(label) || _chapterHint.hasMatch(path) ||
        _urlHint.hasMatch(path) || RegExp(r'^\s*(?:#?\d{1,4}|prologue|epilogue)\b', caseSensitive: false).hasMatch(label);
  }

  bool _isPagination(String label, String rel) =>
      rel.toLowerCase().contains('next') ||
      RegExp(r'^(next|older|more|下一页|下一章)\b', caseSensitive: false).hasMatch(label);

  void close() => _client.close();
}