import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../models/block.dart';

/// Extracts readable blocks and safe inline formatting from chapter HTML.
class WebContentParser {
  static const _skip = [
    'script', 'style', 'noscript', 'nav', 'footer', 'aside', 'form',
    'svg', 'iframe', '[aria-hidden="true"]', '[role="navigation"]',
    '.advertisement', '.ads', '.sidebar', '.comments',
  ];
  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre'
  };
  static const _inlineTags = {
    'strong', 'b', 'em', 'i', 'u', 's', 'code', 'sub', 'sup', 'br'
  };

  static List<Block> parse(String html) {
    final document = html_parser.parse(html);
    final root = _contentRoot(document);
    if (root == null) return const [];
    for (final selector in _skip) {
      for (final element in root.querySelectorAll(selector).toList()) {
        element.remove();
      }
    }
    final blocks = <Block>[];

    void add(dom.Element element, String tag) {
      final text = _clean(element.text);
      if (text.length < 2) return;
      final type = tag.startsWith('h')
          ? BlockType.heading
          : tag == 'li'
              ? BlockType.listItem
              : tag == 'blockquote'
                  ? BlockType.quote
                  : BlockType.paragraph;
      blocks.add(Block(text, type, markup: _inlineChildren(element)));
    }

    void walk(dom.Element element) {
      final tag = (element.localName ?? '').toLowerCase();
      if (_blockTags.contains(tag)) {
        if (element.querySelector(_blockTags.join(',')) != null) {
          for (final child in element.children) { walk(child); }
        } else {
          add(element, tag);
        }
        return;
      }
      if (tag == 'div' && element.querySelector(_blockTags.join(',')) == null) {
        final text = _clean(element.text);
        if (text.length >= 80) {
          blocks.add(Block(text, BlockType.paragraph, markup: _inlineChildren(element)));
          return;
        }
      }
      for (final child in element.children) { walk(child); }
    }

    walk(root);
    if (blocks.isEmpty) {
      final text = _clean(root.text);
      if (text.length >= 80) {
        for (final part in text.split(RegExp(r'(?<=[.!?])\\s{2,}'))) {
          final value = _clean(part);
          if (value.length >= 2) blocks.add(Block(value, BlockType.paragraph));
        }
      }
    }
    return blocks;
  }

  static String _inlineChildren(dom.Element element) =>
      element.nodes.map(_serializeInline).join();

  static String _serializeInline(dom.Node node) {
    if (node is dom.Text) return _escape(node.text);
    if (node is! dom.Element) return '';
    final tag = (node.localName ?? '').toLowerCase();
    final children = node.nodes.map(_serializeInline).join();
    if (tag == 'br') return '<br />';
    if (_inlineTags.contains(tag)) return '<$tag>$children</$tag>';
    if (tag == 'a') {
      final href = node.attributes['href'] ?? '';
      final uri = Uri.tryParse(href);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return '<a href="${_escape(href)}">$children</a>';
      }
    }
    // Unknown wrappers are removed but their readable child text is retained.
    return children;
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static dom.Element? _contentRoot(dom.Document document) {
    const selectors = [
      'article', '[role="main"]', 'main', '.chapter-content',
      '.entry-content', '.post-content', '.article-content', '.content', 'body',
    ];
    for (final selector in selectors) {
      final element = document.querySelector(selector);
      if (element != null && _clean(element.text).length >= 80) return element;
    }
    return document.body ?? document.documentElement;
  }

  static String _clean(String value) =>
      value.replaceAll('\\u00a0', ' ').replaceAll(RegExp(r'\\s+'), ' ').trim();
}
