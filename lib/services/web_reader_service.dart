import '../models/sentence.dart';
import 'speech_controller.dart';

/// Turns a loaded web page into a queue the SpeechController can speak.
class WebReaderService {
  /// Runs in the page. Collects the paragraph-like text of the article /
  /// body, drops duplicates and tiny nodes, returns '\n\n'-separated text.
  static const String extractScript = '''
    (function() {
      try {
        var root = document.querySelector('article, main, [role=main]') || document.body;
        if (!root) return '';
        var nodes = root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote, pre');
        var out = [];
        var seen = {};
        nodes.forEach(function(n) {
          var t = (n.innerText || '').replace(/\\s+/g, ' ').trim();
          if (t.length < 2) return;
          if (seen[t]) return;
          seen[t] = true;
          out.push(t);
        });
        if (out.length === 0) {
          var t = (root.innerText || '').trim();
          if (t) out.push(t);
        }
        return out.join('\\n\\n');
      } catch (e) { return ''; }
    })();
  ''';

  /// Splits extracted page text into paragraphs, then sentences.
  static List<SentenceRef> buildQueue(String rawText) {
    final queue = <SentenceRef>[];
    if (rawText.trim().isEmpty) return queue;
    final paragraphs = rawText
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n[ \t]*\n+'));
    int block = 0;
    for (final p in paragraphs) {
      final text = p.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      if (text.isEmpty) continue;
      for (final s in splitSentences(text)) {
        queue.add(SentenceRef(0, block, s));
      }
      block++;
    }
    return queue;
  }
}
