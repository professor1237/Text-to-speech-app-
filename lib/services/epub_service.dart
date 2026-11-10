import 'dart:typed_data';
import 'package:epubx/epubx.dart' as epub;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../models/block.dart';

class Chapter {
  final String title;
  final List<Block> blocks;
  Chapter(this.title, this.blocks);
}

class BookContent {
  final String title;
  final String author;
  final Uint8List? cover;
  final List<Chapter> chapters;
  BookContent(this.title, this.author, this.cover, this.chapters);
}

class EpubService {
  static Future<BookContent> parse(Uint8List bytes) async {
    final book = await epub.EpubReader.readBook(bytes);
    final chapters = <Chapter>[];

    void collect(List<epub.EpubChapter>? list) {
      for (final c in list ?? <epub.EpubChapter>[]) {
        final html = c.HtmlContent;
        if (html != null && html.trim().isNotEmpty) {
          final blocks = _htmlToBlocks(html);
          if (blocks.isNotEmpty) chapters.add(Chapter(c.Title ?? '', blocks));
        }
        collect(c.SubChapters);
      }
    }

    collect(book.Chapters);
    return BookContent(
      book.Title ?? 'Untitled',
      book.Author ?? 'Unknown',
      _extractCover(book),
      chapters,
    );
  }

  static Uint8List? _extractCover(epub.EpubBook book) {
    try {
      final dynamic img = book.CoverImage;
      if (img == null) return null;
      final dynamic content = img.Content;
      if (content is Uint8List) return content;
      if (content is List<int>) return Uint8List.fromList(content);
      return null;
    } catch (_) {
      return null;
    }
  }

  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'blockquote', 'pre'
  };
  static const _skipTags = {'script', 'style', 'head', 'nav', 'svg', 'noscript'};

  static List<Block> _htmlToBlocks(String html) {
    final doc = html_parser.parse(html).documentElement;
    final out = <Block>[];
    if (doc == null) return out;

    void walk(dom.Element el) {
      final tag = el.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) return;
      if (_blockTags.contains(tag)) {
        final text = _normalize(el.text);
        if (text.isNotEmpty) out.add(Block(text, _typeOf(tag)));
        return;
      }
      for (final child in el.children) walk(child);
    }

    walk(doc);
    return out;
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'[\u00A0\s]+'), ' ').trim();

  static BlockType _typeOf(String tag) {
    if (tag.startsWith('h')) return BlockType.heading;
    if (tag == 'li') return BlockType.listItem;
    if (tag == 'blockquote') return BlockType.quote;
    return BlockType.paragraph;
  }
}
