import '../models/sentence.dart';
import 'speech_controller.dart';

/// Turns a loaded web page into a queue the SpeechController can speak.
class WebReaderService {
  /// Runs in the page. Collects the paragraph-like text of the article /
  /// body. It skips menus, footers, forms and hidden elements, and never
  /// reads the same text twice (a <li> that wraps a <p> is read once).
  /// Returns paragraphs separated by a blank line.
  static const String extractScript = r'''
    (function() {
      try {
        var root = document.querySelector('article, main, [role=main]') || document.body;
        if (!root) return '';
        var sel = 'p, h1, h2, h3, h4, h5, h6, li, blockquote, pre';
        var skip = 'nav, footer, aside, form, script, style, noscript, ' +
                   '[aria-hidden=true], [role=navigation], [role=contentinfo]';
        var nodes = root.querySelectorAll(sel);
        var out = [];
        var seen = {};
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          var s = n.closest(skip);
          if (s && s !== root && root.contains(s)) continue;
          if (n.querySelector(sel)) continue;
          var st = window.getComputedStyle(n);
          if (st.display === 'none' || st.visibility === 'hidden') continue;
          var t = (n.innerText || '').replace(/\s+/g, ' ').trim();
          if (t.length < 2 || seen[t]) continue;
          seen[t] = true;
          out.push(t);
        }
        if (out.length === 0) {
          var all = (root.innerText || '').trim();
          if (all) out.push(all);
        }
        return out.join('\n\n');
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
