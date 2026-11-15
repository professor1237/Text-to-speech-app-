import 'package:flutter_test/flutter_test.dart';
import 'package:tts_reader/models/block.dart';
import 'package:tts_reader/services/epub_service.dart';
import 'package:tts_reader/services/epub_writer_service.dart';

void main() {
  test('generated EPUB can be parsed by the existing EPUB reader', () async {
    final source = BookContent(
      'A <Novel> & More',
      'Test Author',
      null,
      [
        Chapter('Chapter 1', const [
          Block('A paragraph with <tags> & ampersands.', BlockType.paragraph),
          Block('A heading', BlockType.heading),
          Block('A quotation.', BlockType.quote),
        ]),
        Chapter('Chapter 2', const [
          Block('Second chapter content.', BlockType.paragraph),
        ]),
      ],
    );

    final bytes = EpubWriterService.write(source);
    expect(bytes, isNotEmpty);

    final parsed = await EpubService.parse(bytes);
    expect(parsed.title, 'A <Novel> & More');
    expect(parsed.chapters, isNotEmpty);
    expect(parsed.chapters.any((c) => c.blocks.any(
      (b) => b.text.contains('ampersands'),
    )), isTrue);
  });
}
