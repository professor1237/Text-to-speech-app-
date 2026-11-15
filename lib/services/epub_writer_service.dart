import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/block.dart';
import 'epub_service.dart';

/// Creates an EPUB 3 archive from the reader's BookContent model.
class EpubWriterService {
  static Uint8List write(BookContent book) {
    if (book.chapters.isEmpty) throw ArgumentError('An EPUB needs at least one chapter.');
    final archive = Archive();
    final suffix = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    final bookId = 'urn:uuid:00000000-0000-4000-8000-${suffix.substring(suffix.length - 12)}';
    final mime = utf8.encode('application/epub+zip');
    final mimeFile = ArchiveFile('mimetype', mime.length, mime)..compress = false;
    archive.addFile(mimeFile);
    _addText(archive, 'META-INF/container.xml', _containerXml);
    _addText(archive, 'OEBPS/nav.xhtml', _nav(book.chapters));
    _addText(archive, 'OEBPS/toc.ncx', _ncx(book, bookId));
    _addText(archive, 'OEBPS/content.opf', _opf(book, bookId));
    for (var i = 0; i < book.chapters.length; i++) {
      _addText(archive, 'OEBPS/${_chapterFile(i)}', _chapter(book.chapters[i]));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null || encoded.isEmpty) throw StateError('EPUB archive creation failed.');
    return Uint8List.fromList(encoded);
  }

  static void _addText(Archive archive, String name, String value) {
    final bytes = utf8.encode(value);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static String _chapterFile(int i) => 'chapter_${(i + 1).toString().padLeft(4, '0')}.xhtml';

  static String _e(String s) => s.replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  static const _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
 <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

  static String _nav(List<Chapter> chapters) {
    final items = <String>[];
    for (var i = 0; i < chapters.length; i++) {
      items.add('<li><a href="${_chapterFile(i)}">${_e(chapters[i].title)}</a></li>');
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
<head><title>Contents</title><meta charset="utf-8"/></head>
<body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>${items.join()}</ol></nav></body>
</html>''';
  }

  static String _ncx(BookContent book, String bookId) {
    final points = <String>[];
    for (var i = 0; i < book.chapters.length; i++) {
      points.add('<navPoint id="np${i + 1}" playOrder="${i + 1}"><navLabel><text>${_e(book.chapters[i].title)}</text></navLabel><content src="${_chapterFile(i)}"/></navPoint>');
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="${_e(bookId)}"/></head>
<docTitle><text>${_e(book.title)}</text></docTitle><navMap>${points.join()}</navMap></ncx>''';
  }

  static String _opf(BookContent book, String bookId) {
    final manifest = <String>[
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    ];
    final spine = <String>[];
    for (var i = 0; i < book.chapters.length; i++) {
      final id = 'ch${i + 1}';
      manifest.add('<item id="$id" href="${_chapterFile(i)}" media-type="application/xhtml+xml"/>');
      spine.add('<itemref idref="$id"/>');
    }
    final title = book.title.trim().isEmpty ? 'Untitled' : book.title.trim();
    final author = book.author.trim().isEmpty ? 'Unknown' : book.author.trim();
    final modified = DateTime.now().toUtc().toIso8601String().split('.').first + 'Z';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="en">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">${_e(bookId)}</dc:identifier><dc:title>${_e(title)}</dc:title>
<dc:creator>${_e(author)}</dc:creator><dc:language>en</dc:language>
<meta property="dcterms:modified">$modified</meta></metadata>
<manifest>${manifest.join()}</manifest><spine toc="ncx">${spine.join()}</spine></package>''';
  }

  static String _chapter(Chapter chapter) {
    final body = <String>['<h1>${_e(chapter.title)}</h1>'];
    for (final block in chapter.blocks) {
      // markup is produced by WebContentParser's allow-list serializer. Legacy
      // blocks have no markup and continue to be escaped as plain text.
      final value = block.markup ?? _e(block.text);
      switch (block.type) {
        case BlockType.heading: body.add('<h2>$value</h2>'); break;
        case BlockType.listItem: body.add('<p class="list-item">$value</p>'); break;
        case BlockType.quote: body.add('<blockquote><p>$value</p></blockquote>'); break;
        case BlockType.paragraph: body.add('<p>$value</p>'); break;
      }
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head><title>${_e(chapter.title)}</title><meta charset="utf-8"/></head>
<body>${body.join()}</body></html>''';
  }
}