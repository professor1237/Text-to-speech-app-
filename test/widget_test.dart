import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_reader/models/sentence.dart';
import 'package:tts_reader/models/term_rule.dart';
import 'package:tts_reader/services/book_parser.dart';

void main() {
  group('splitSentences', () {
    test('keeps common abbreviations and decimal numbers together', () {
      final sentences = splitSentences('Dr. Rao paid 3.5 rupees. Next!');
      expect(
        sentences.map((sentence) => sentence.text.trim()).toList(),
        ['Dr. Rao paid 3.5 rupees.', 'Next!'],
      );
    });

    test('does not create empty sentences for whitespace', () {
      expect(splitSentences('   \n  '), isEmpty);
    });
  });

  group('term replacement', () {
    test('supports case-insensitive plain-text rules', () {
      final result = applyTermRules(
        'Hello PROFESSOR',
        [TermRule(find: 'professor', replace: 'reader', caseSensitive: false)],
      );
      expect(result, 'Hello reader');
    });

    test('skips invalid regular expressions safely', () {
      final result = applyTermRules(
        'Keep this text',
        [TermRule(find: '[', replace: 'ignored', regex: true)],
      );
      expect(result, 'Keep this text');
    });
  });

  test('parses UTF-8 text files into readable paragraphs', () async {
    final bytes = Uint8List.fromList(
      utf8.encode('First paragraph.\n\nSecond paragraph.'),
    );
    final book = await BookParser.parse(
      BookInput('sample.txt', bytes, 'Sample'),
    );
    final paragraphs = book.chapters
        .expand((chapter) => chapter.blocks)
        .map((block) => block.text)
        .toList();

    expect(paragraphs, ['First paragraph.', 'Second paragraph.']);
  });
}
