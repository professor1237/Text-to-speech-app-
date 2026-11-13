import '../models/sentence.dart';
import 'speech_controller.dart';

/// Turns a loaded web page into a queue the SpeechController can speak.
class WebReaderService {
  /// Runs in the page. Collects readable paragraph-like text while skipping
  /// menus, footers, forms and hidden elements. Returns paragraphs separated
  /// by a blank line.
  static const String extractScript = r'''
    (function() {
      try {
        var root = document.querySelector('article, main, [role=main], .post, .entry-content, .article-body') || document.body;
        if (!root) return '';

        var skipSel = 'nav, footer, aside, form, script, style, noscript, header, ' +
                      '[aria-hidden="true"], [role=navigation], [role=contentinfo], ' +
                      '[role=banner], .nav, .menu, .sidebar, .footer, .header, .ad, .ads, .advertisement';

        var blockSel = 'p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, td, th, figcaption, dt, dd';
        var nodes = root.querySelectorAll(blockSel);
        var out = [];
        var seen = {};

        function isVisible(el) {
          var st = window.getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return false;
          if (el.offsetParent === null && st.position !== 'fixed') return false;
          return true;
        }

        function clean(t) {
          return (t || '').replace(/\u00A0/g, ' ').replace(/\s+/g, ' ').trim();
        }

        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];

          var skip = n.closest(skipSel);
          if (skip && skip !== root && root.contains(skip)) continue;

          if (n.querySelector(blockSel)) continue;

          if (!isVisible(n)) continue;

          var t = clean(n.innerText);
          if (t.length < 2) continue;

          if (seen[t]) continue;
          seen[t] = true;

          out.push(t);
        }

        if (out.length === 0) {
          var all = clean(root.innerText);
          if (all) {
            var parts = all.split(/\n+/);
            for (var j = 0; j < parts.length; j++) {
              var p = clean(parts[j]);
              if (p.length >= 2) out.push(p);
            }
          }
        }

        return out.join('\n\n');
      } catch (e) {
        return '';
      }
    })();
  ''';

  /// Injected after page load. Listens for double-click and sends the nearest
  /// readable text snippet to Flutter via the TtsReader channel.
  static const String doubleTapScript = r'''
    (function() {
      if (window.__ttsDblTapInstalled) return;
      window.__ttsDblTapInstalled = true;

      function nearestText(el) {
        if (!el) return '';
        var cur = el.nodeType === 3 ? el.parentElement : el;
        for (var i = 0; i < 8 && cur; i++) {
          var t = (cur.innerText || '').replace(/\s+/g, ' ').trim();
          if (t.length >= 8) return t.substring(0, 400);
          cur = cur.parentElement;
        }
        try {
          var sel = window.getSelection();
          if (sel && sel.toString().trim().length > 0) {
            return sel.toString().replace(/\s+/g, ' ').trim().substring(0, 400);
          }
        } catch (_) {}
        return '';
      }

      document.addEventListener('dblclick', function(e) {
        try {
          var text = nearestText(e.target);
          if (text && text.length >= 2 && window.TtsReader) {
            window.TtsReader.postMessage(text);
          }
        } catch (_) {}
      }, true);
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
        if (s.text.trim().length < 2) continue;
        queue.add(SentenceRef(0, block, s));
      }
      block++;
    }
    return queue;
  }

  /// Find the best sentence index that matches a double-tap snippet.
  static int findBestSentenceIndex(List<SentenceRef> queue, String snippet) {
    final needle = snippet.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    if (needle.isEmpty || queue.isEmpty) return -1;

    int best = -1;
    int bestScore = 0;
    for (int i = 0; i < queue.length; i++) {
      final hay = queue[i].sentence.text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      if (hay.isEmpty) continue;

      if (hay == needle) return i;

      if (hay.contains(needle) || needle.contains(hay)) {
        final score = hay.length < needle.length ? hay.length : needle.length;
        if (score > bestScore) {
          bestScore = score;
          best = i;
        }
      }
    }
    if (best >= 0 && bestScore >= 12) return best;

    final prefix = needle.length > 80 ? needle.substring(0, 80) : needle;
    for (int i = 0; i < queue.length; i++) {
      final hay = queue[i].sentence.text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      if (hay.startsWith(prefix) ||
          (hay.length >= 20 &&
              prefix.startsWith(hay.substring(0, hay.length.clamp(0, 40))))) {
        return i;
      }
    }

    final words = needle
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 3)
        .toSet();
    if (words.isEmpty) return best;

    best = -1;
    bestScore = 0;
    for (int i = 0; i < queue.length; i++) {
      final hay = queue[i].sentence.text.toLowerCase();
      var score = 0;
      for (final w in words) {
        if (hay.contains(w)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return bestScore >= 2 ? best : -1;
  }
}
