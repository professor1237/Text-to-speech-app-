class Sentence {
  final String text;
  final int start;
  final int end;
  const Sentence(this.text, this.start, this.end);
}

const _enders = '.!?\u2026\u3002\uFF01\uFF1F';
const _closers = '"\'\u201D\u2019)]';

const _titles = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'inc',
  'ltd', 'co', 'vol', 'fig', 'mt', 'gen', 'col', 'capt', 'lt', 'sgt',
};

bool _isLetter(int u) =>
    (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
bool _isDigit(int u) => u >= 48 && u <= 57;
bool _isUpper(int u) => u >= 65 && u <= 90;

/// Returns true when a dot is part of a number, domain, filename, or
/// abbreviation rather than a sentence boundary.
bool _isFalseEnd(String text, int i) {
  if (text[i] != '.') return false;

  // Decimal numbers such as 3.5.
  if (i > 0 && i + 1 < text.length &&
      _isDigit(text.codeUnitAt(i - 1)) &&
      _isDigit(text.codeUnitAt(i + 1))) return true;

  // A dot inside a URL, domain, or filename has no following whitespace.
  if (i + 1 < text.length && !_isWhitespace(text.codeUnitAt(i + 1))) {
    return true;
  }

  var start = i;
  while (start > 0 && _isLetter(text.codeUnitAt(start - 1))) {
    start--;
  }
  final word = text.substring(start, i).toLowerCase();
  if (word.isEmpty) return false;

  // Initials only suppress a boundary when another capitalized name follows.
  final next = _nextNonWhitespace(text, i + 1);
  if (word.length == 1) {
    // Keep the second initial in "J. R. Tolkien".
    if (start >= 2 && text[start - 1] == ' ' && text[start - 2] == '.') {
      return true;
    }
    // Keep paired initials such as "J. R. Tolkien", but allow a single
    // letter at the end of a phrase ("Plan B. Next") to end the sentence.
    if (next + 2 < text.length &&
        _isUpper(text.codeUnitAt(next)) &&
        text[next + 1] == '.' &&
        _isWhitespace(text.codeUnitAt(next + 2))) {
      final afterInitial = _nextNonWhitespace(text, next + 2);
      if (afterInitial < text.length &&
          _isUpper(text.codeUnitAt(afterInitial))) return true;
    }
    return false;
  }

  // Titles are abbreviations even before a capitalized name ("Dr. Rao").
  if (_titles.contains(word)) return true;

  // General abbreviations such as "etc." and "no." are context-sensitive:
  // keep them attached when followed by a lowercase continuation, but allow
  // a real sentence boundary before a new capitalized sentence.
  if (word == 'etc' || word == 'no') {
    return next < text.length && !_isUpper(text.codeUnitAt(next));
  }
  return false;
}

bool _isWhitespace(int u) =>
    u == 0x20 || (u >= 0x09 && u <= 0x0D) || u == 0xA0;

int _nextNonWhitespace(String text, int from) {
  var i = from;
  while (i < text.length && _isWhitespace(text.codeUnitAt(i))) {
    i++;
  }
  return i;
}

List<Sentence> splitSentences(String text) {
  final out = <Sentence>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (!_enders.contains(text[i])) continue;
    // Treat runs such as "..." and "?!" as one ending.
    if (i + 1 < text.length && _enders.contains(text[i + 1])) continue;
    if (_isFalseEnd(text, i)) continue;

    var end = i + 1;
    while (end < text.length && _closers.contains(text[end])) {
      end++;
    }
    // Punctuation in the middle of a token is not a boundary.
    if (end < text.length && !_isWhitespace(text.codeUnitAt(end))) continue;

    final chunk = text.substring(start, end);
    if (chunk.trim().isNotEmpty) out.add(Sentence(chunk, start, end));
    start = end;
    i = end - 1;
  }
  if (start < text.length) {
    final chunk = text.substring(start);
    if (chunk.trim().isNotEmpty) {
      out.add(Sentence(chunk, start, text.length));
    }
  }
  return out;
}
