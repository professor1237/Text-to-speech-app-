import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:xml/xml.dart';

import '../models/block.dart';
import 'epub_service.dart';

/// File types the app can open.
const supportedBookExtensions = <String>[
  'epub',
  'pdf',
  'txt',
  'docx',
  'html',
  'htm',
  'xhtml',
  'md',
  'markdown',
];

String extensionOf(String fileName) {
  final n = fileName.replaceAll('\\', '/');
  final name = n.substring(n.lastIndexOf('/') + 1);
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String baseName(String fileName) {
  final n = fileName.replaceAll('\\', '/');
  final name = n.substring(n.lastIndexOf('/') + 1);
  final i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}

/// Everything the background worker needs to open a file.
class BookInput {
  final String fileName; // used to find the file type (.pdf, .txt ...)
  final Uint8List bytes;
  final String titleHint; // used when the file has no title inside
  const BookInput(this.fileName, this.bytes, this.titleHint);
}

class BookParser {
  static Future<BookContent> parse(BookInput input) async {
    final ext = extensionOf(input.fileName);
    switch (ext) {
      case 'epub':
        return EpubService.parse(input.bytes);
      case 'pdf':
        return _parsePdf(input);
      case 'txt':
        return _parseText(input);
      case 'docx':
        return _parseDocx(input);
      case 'html':
      case 'htm':
      case 'xhtml':
        return _parseHtml(input);
      case 'md':
      case 'markdown':
        return _parseMarkdown(input);
      default:
        throw Exception('Unsupported file type: .$ext');
    }
  }

  // ------------------------------------------------------------------
  // Shared helpers
  // ------------------------------------------------------------------

  static BookContent _finish(
    BookInput i,
    List<Block> blocks, {
    String? title,
    String author = 'Unknown',
  }) {
    if (blocks.isEmpty) {
      throw Exception('No readable text found in this file.');
    }
    final t = (title == null || title.trim().isEmpty) ? i.titleHint : title.trim();
    return BookContent(t, author, null, _buildChapters(blocks, t));
  }

  /// Split into chapters at headings. If there are no headings,
  /// cut into parts of roughly the same size.
  static List<Chapter> _buildChapters(List<Block> blocks, String firstTitle) {
    final chapters = <Chapter>[];
    var title = firstTitle;
    var cur = <Block>[];

    void flush() {
      if (cur.isNotEmpty) chapters.add(Chapter(title, cur));
      cur = <Block>[];
    }

    for (final b in blocks) {
      if (b.type == BlockType.heading) {
        flush();
        title = b.text.length > 80 ? b.text.substring(0, 80) : b.text;
      }
      cur.add(b);
    }
    flush();

    if (chapters.length > 1) return chapters;
    return _chunkBySize(blocks, firstTitle);
  }

  static List<Chapter> _chunkBySize(List<Block> blocks, String singleTitle,
      {int target = 8000}) {
    final out = <Chapter>[];
    var cur = <Block>[];
    var size = 0;
    for (final b in blocks) {
      cur.add(b);
      size += b.text.length;
      if (size >= target) {
        out.add(Chapter('Part ${out.length + 1}', cur));
        cur = <Block>[];
        size = 0;
      }
    }
    if (cur.isNotEmpty) out.add(Chapter('Part ${out.length + 1}', cur));
    if (out.length == 1) return [Chapter(singleTitle, blocks)];
    return out;
  }

  static final _numberedHeading = RegExp(
      r'^(chapter|part|book|section)\s+(\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b',
      caseSensitive: false);
  static final _namedHeading = RegExp(
      r'^(prologue|epilogue|preface|introduction|foreword|afterword|appendix)\b',
      caseSensitive: false);

  static bool _looksLikeHeading(String p) {
    if (p.length > 80) return false;
    if (_numberedHeading.hasMatch(p)) return true;
    return p.length <= 40 && _namedHeading.hasMatch(p);
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ------------------------------------------------------------------
  // TXT
  // ------------------------------------------------------------------

  static String _decodeText(Uint8List b) {
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      return _utf16(b, Endian.little);
    }
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      return _utf16(b, Endian.big);
    }
    String s;
    try {
      s = utf8.decode(b);
    } on FormatException {
      s = latin1.decode(b);
    }
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) s = s.substring(1);
    return s;
  }

  static String _utf16(Uint8List b, Endian endian) {
    final bd = ByteData.sublistView(b);
    final units = <int>[];
    for (int i = 2; i + 1 < b.length; i += 2) {
      units.add(bd.getUint16(i, endian));
    }
    return String.fromCharCodes(units);
  }

  static List<String> _splitParagraphs(String text) {
    final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    var paras = t.split(RegExp(r'\n[ \t]*\n+'));
    // Some text files have no blank lines: then every line is a paragraph.
    if (paras.length < 3 && t.length > 2000) paras = t.split('\n');
    return paras.map(_normalize).where((p) => p.isNotEmpty).toList();
  }

  static BookContent _parseText(BookInput i) {
    final blocks = <Block>[];
    for (final p in _splitParagraphs(_decodeText(i.bytes))) {
      blocks.add(Block(
          p, _looksLikeHeading(p) ? BlockType.heading : BlockType.paragraph));
    }
    return _finish(i, blocks);
  }

  // ------------------------------------------------------------------
  // Markdown
  // ------------------------------------------------------------------

  static String _cleanMd(String s) {
    var t = s;
    t = t.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    t = t.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    t = t.replaceAll(RegExp(r'(\*\*|__|\*|_|~~|`)'), '');
    return _normalize(t);
  }

  static BookContent _parseMarkdown(BookInput i) {
    final lines =
        _decodeText(i.bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <Block>[];
    final para = StringBuffer();
    var inCode = false;

    void flush() {
      final t = _cleanMd(para.toString());
      if (t.isNotEmpty) blocks.add(Block(t, BlockType.paragraph));
      para.clear();
    }

    final headingRe = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
    final ruleRe = RegExp(r'^\s*([-*_]\s*){3,}$');
    final listRe = RegExp(r'^\s*([-*+]|\d+[.)])\s+(.*)$');

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('```')) {
        inCode = !inCode;
        flush();
        continue;
      }
      if (inCode) continue; // code is not read aloud
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final h = headingRe.firstMatch(line);
      if (h != null) {
        flush();
        final t = _cleanMd(h.group(2) ?? '');
        if (t.isNotEmpty) blocks.add(Block(t, BlockType.heading));
        continue;
      }
      if (ruleRe.hasMatch(line)) {
        flush();
        continue;
      }
      final li = listRe.firstMatch(line);
      if (li != null) {
        flush();
        final t = _cleanMd(li.group(2) ?? '');
        if (t.isNotEmpty) blocks.add(Block(t, BlockType.listItem));
        continue;
      }
      if (line.trimLeft().startsWith('>')) {
        flush();
        final t = _cleanMd(line.trimLeft().substring(1));
        if (t.isNotEmpty) blocks.add(Block(t, BlockType.quote));
        continue;
      }
      if (para.isNotEmpty) para.write(' ');
      para.write(line.trim());
    }
    flush();
    return _finish(i, blocks);
  }

  // ------------------------------------------------------------------
  // HTML
  // ------------------------------------------------------------------

  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre',
    'td', 'th'
  };
  static const _skipTags = {'script', 'style', 'head', 'nav', 'svg', 'noscript'};

  static BlockType _htmlType(String tag) {
    if (tag.startsWith('h')) return BlockType.heading;
    if (tag == 'li') return BlockType.listItem;
    if (tag == 'blockquote') return BlockType.quote;
    return BlockType.paragraph;
  }

  static List<Block> _htmlToBlocks(String html) {
    final root = html_parser.parse(html).documentElement;
    final out = <Block>[];
    if (root == null) return out;

    String textWithBreaks(dom.Node node) {
      if (node is dom.Text) return node.text;
      if (node is dom.Element && node.localName?.toLowerCase() == 'br') {
        return '\\n';
      }
      if (node is dom.Element &&
          _skipTags.contains(node.localName?.toLowerCase() ?? '')) return '';
      return node.nodes.map(textWithBreaks).join();
    }

    void addTextBlock(dom.Element el, BlockType type) {
      final raw = textWithBreaks(el);
      for (final part in raw.split(RegExp(r'\\n+'))) {
        final text = _normalize(part);
        if (text.isNotEmpty) out.add(Block(text, type));
      }
    }

    void walk(dom.Element el) {
      final tag = el.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) return;
      if (_blockTags.contains(tag)) {
        addTextBlock(el, _htmlType(tag));
        return;
      }
      // Some EPUBs contain only divs (or table cells) instead of paragraphs.
      // Treat a div as a block only when it has no semantic child blocks.
      if (tag == 'div' &&
          el.querySelector(_blockTags.join(',')) == null) {
        addTextBlock(el, BlockType.paragraph);
        return;
      }
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(root);
    return out;
  }

  static BookContent _parseHtml(BookInput i) {
    final html = _decodeText(i.bytes);
    final doc = html_parser.parse(html);
    final title = doc.querySelector('title')?.text.trim();
    var blocks = _htmlToBlocks(html);
    if (blocks.isEmpty) {
      // page without <p> tags: use all of its text
      final body = doc.body?.text ?? '';
      blocks = _splitParagraphs(body)
          .map((p) => Block(p, BlockType.paragraph))
          .toList();
    }
    return _finish(i, blocks, title: title);
  }

  // ------------------------------------------------------------------
  // DOCX
  // ------------------------------------------------------------------

  static BookContent _parseDocx(BookInput i) {
    final archive = ZipDecoder().decodeBytes(i.bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) {
      throw Exception('This does not look like a valid .docx file.');
    }
    final xml = XmlDocument.parse(
        utf8.decode(entry.content as List<int>, allowMalformed: true));

    final blocks = <Block>[];
    final paragraphs = xml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p');

    for (final p in paragraphs) {
      final buf = StringBuffer();
      var style = '';
      var isList = false;
      for (final n in p.descendants.whereType<XmlElement>()) {
        switch (n.name.local) {
          case 't':
            buf.write(n.innerText);
            break;
          case 'tab':
          case 'br':
            buf.write(' ');
            break;
          case 'numPr':
            isList = true;
            break;
          case 'pStyle':
            for (final a in n.attributes) {
              if (a.name.local == 'val') style = a.value.toLowerCase();
            }
            break;
        }
      }
      final text = _normalize(buf.toString());
      if (text.isEmpty) continue;
      final isHeading = style.startsWith('heading') || style == 'title';
      blocks.add(Block(
        text,
        isHeading
            ? BlockType.heading
            : (isList ? BlockType.listItem : BlockType.paragraph),
      ));
    }
    return _finish(i, blocks);
  }

  // ------------------------------------------------------------------
  // PDF
  // ------------------------------------------------------------------

  static BookContent _parsePdf(BookInput i) {
    sf.PdfDocument doc;
    try {
      doc = sf.PdfDocument(inputBytes: i.bytes);
    } catch (_) {
      throw Exception(
          'Could not open this PDF. It may be password-protected or damaged.');
    }
    try {
      final pages = doc.pages.count;
      final extractor = sf.PdfTextExtractor(doc);
      final chapters = <Chapter>[];
      const group = 5; // pages per chapter

      for (int s = 0; s < pages; s += group) {
        final e = (s + group - 1) < pages ? s + group - 1 : pages - 1;
        final raw = extractor.extractText(startPageIndex: s, endPageIndex: e);
        final blocks = _pdfTextToBlocks(raw);
        if (blocks.isEmpty) continue;
        chapters.add(Chapter(
            s == e ? 'Page ${s + 1}' : 'Pages ${s + 1}\u2013${e + 1}', blocks));
      }
      if (chapters.isEmpty) {
        throw Exception(
            'No readable text found. This PDF may be made of scanned images.');
      }

      String title = i.titleHint;
      String author = 'Unknown';
      try {
        final t = doc.documentInformation.title.trim();
        if (t.isNotEmpty) title = t;
        final a = doc.documentInformation.author.trim();
        if (a.isNotEmpty) author = a;
      } catch (_) {}

      return BookContent(title, author, null, chapters);
    } finally {
      doc.dispose();
    }
  }

  /// PDF text comes as many short lines. Join them back into paragraphs.
  static List<Block> _pdfTextToBlocks(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim())
        .toList();

    var maxLen = 0;
    for (final l in lines) {
      if (l.length > maxLen) maxLen = l.length;
    }

    final blocks = <Block>[];
    final buf = StringBuffer();
    final pageNumber = RegExp(r'^\d{1,4}$');
    final sentenceEnd = RegExp(r'[.!?:"\u201D\u2019)]$');
    var prev = '';

    void flush() {
      final t = _normalize(buf.toString());
      if (t.isNotEmpty) {
        blocks.add(Block(
            t, _looksLikeHeading(t) ? BlockType.heading : BlockType.paragraph));
      }
      buf.clear();
    }

    for (final l in lines) {
      if (l.isEmpty) {
        flush();
        prev = '';
        continue;
      }
      if (pageNumber.hasMatch(l)) continue; // lone page numbers
      if (buf.isNotEmpty) {
        final endsSentence = sentenceEnd.hasMatch(prev);
        final prevShort = prev.length < maxLen * 0.7;
        if (endsSentence && prevShort) {
          flush();
        } else if (prev.endsWith('-') && prev.length > 1) {
          // word split across two lines: remove the hyphen and join
          final s = buf.toString();
          buf.clear();
          buf.write(s.substring(0, s.length - 1));
        } else {
          buf.write(' ');
        }
      }
      buf.write(l);
      prev = l;
    }
    flush();
    return blocks;
  }
}
