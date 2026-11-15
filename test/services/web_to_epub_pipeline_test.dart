import 'package:flutter_test/flutter_test.dart';
import 'package:tts_reader/models/block.dart';
import 'package:tts_reader/models/web_chapter.dart';
import 'package:tts_reader/services/chapter_discovery_service.dart';
import 'package:tts_reader/services/epub_service.dart';
import 'package:tts_reader/services/epub_writer_service.dart';
import 'package:tts_reader/services/web_content_parser.dart';
import 'package:tts_reader/services/web_epub_settings_service.dart';

void main() {
  group('ChapterDiscoveryService', () {
    test('discovers and deduplicates chapter links from a rendered TOC', () {
      final service = ChapterDiscoveryService();
      final chapters = service.discoverFromHtml('''
        <html><body><main>
          <a href="/novel/chapter-1">Chapter 1: Start</a>
          <a href="/novel/chapter-2">Chapter 2: Continue</a>
          <a href="/novel/chapter-1">Chapter 1 duplicate</a>
          <a href="https://other.example/chapter-3">Chapter 3 external</a>
          <a href="/about">About</a>
        </main></body></html>
      ''', 'https://stories.example/novel/');
      service.close();
      expect(chapters, hasLength(2));
      expect(chapters.map((c) => c.url).toList(), [
        'https://stories.example/novel/chapter-1',
        'https://stories.example/novel/chapter-2',
      ]);
    });

    test('finds chapter links outside the first article or main container', () {
      final service = ChapterDiscoveryService();
      final chapters = service.discoverFromHtml('''
        <html><body>
          <main><article><h1>Novel description</h1><p>About this novel</p></article></main>
          <section class="chapter-list">
            <a href="/novel/chapter-1">1.1 So it Begins~</a>
            <a href="/novel/chapter-2">1.2 Not a System~</a>
          </section>
        </body></html>
      ''', 'https://novelphoenix.com/novel/example');
      service.close();
      expect(chapters, hasLength(2));
      expect(chapters.first.title, '1.1 So it Begins~');
      expect(chapters.last.url, 'https://novelphoenix.com/novel/chapter-2');
    });

    test('returns no chapters when the page has no chapter links', () {
      final service = ChapterDiscoveryService();
      final chapters = service.discoverFromHtml(
        '<html><body><a href="/about">About</a></body></html>',
        'https://stories.example/',
      );
      service.close();
      expect(chapters, isEmpty);
    });
  });

  group('EpubWriterService', () {
    test('writes a multi-chapter EPUB that the existing reader parser can reopen', () async {
      final bytes = EpubWriterService.write(BookContent(
        'Test Novel',
        'Test Author',
        null,
        [
          Chapter('Chapter One', [
            const Block('A readable first paragraph with enough text.', BlockType.paragraph),
            const Block('A section heading', BlockType.heading),
          ]),
          Chapter('Chapter Two', [
            const Block('A second chapter paragraph with readable content.', BlockType.paragraph),
          ]),
        ],
      ));
      expect(bytes, isNotEmpty);
      final parsed = await EpubService.parse(bytes);
      expect(parsed.title, 'Test Novel');
      expect(parsed.author, 'Test Author');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters.first.title, 'Chapter One');
      expect(parsed.chapters.last.title, 'Chapter Two');
    });
  });


  group('WebContentParser', () {
    test('footnote references and footnote text follow separate settings', () {
      WebEpubSettingsService.cleaning['footnoteReferences'] = true;
      WebEpubSettingsService.cleaning['footnoteText'] = false;
      const html = '''
        <html><body><article>
          <p>This is a sufficiently long paragraph with a footnote marker
          <sup><a href="#fn1" class="footnote-ref">1</a></sup> in the middle.</p>
          <ol class="footnotes"><li id="fn1">This is the explanatory footnote text.</li></ol>
          <p>This is another sufficiently long paragraph so the chapter is valid.</p>
        </article></body></html>
      ''';
      var blocks = WebContentParser.parse(html);
      expect(blocks.any((b) => b.text.contains('footnote marker 1')), isFalse);
      expect(blocks.any((b) => b.text.contains('explanatory footnote text')), isTrue);

      WebEpubSettingsService.cleaning['footnoteReferences'] = false;
      WebEpubSettingsService.cleaning['footnoteText'] = true;
      blocks = WebContentParser.parse(html);
      expect(blocks.any((b) => b.text.contains('footnote marker 1')), isTrue);
      expect(blocks.any((b) => b.text.contains('explanatory footnote text')), isFalse);

      WebEpubSettingsService.cleaning['footnoteReferences'] = true;
      WebEpubSettingsService.cleaning['footnoteText'] = false;
    });

    test('preserves safe inline formatting and removes unsafe elements', () {
      final blocks = WebContentParser.parse('''
        <html><body><article>
          <p>This is a sufficiently long chapter paragraph with
          <strong>bold text</strong>, <em>italic text</em> and
          <a href="https://example.com/source">a source link</a>.
          <a href="javascript:alert(1)">unsafe link</a>
          <script>secret()</script></p>
        </article></body></html>
      ''');
      expect(blocks, hasLength(1));
      expect(blocks.single.markup, contains('<strong>bold text</strong>'));
      expect(blocks.single.markup, contains('<em>italic text</em>'));
      expect(blocks.single.markup, contains('href="https://example.com/source"'));
      expect(blocks.single.markup, isNot(contains('javascript:')));
      expect(blocks.single.markup, isNot(contains('secret()')));
    });
  });

  test('chapter status starts pending and selected', () {
    final chapter = WebChapter(
      title: 'Chapter 1',
      url: 'https://stories.example/chapter-1',
      order: 0,
    );
    expect(chapter.selected, isTrue);
    expect(chapter.status, ChapterDownloadStatus.pending);
    expect(chapter.blocks, isEmpty);
  });
}
