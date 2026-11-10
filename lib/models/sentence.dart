class Sentence {
  final String text;
  final int start;
  final int end;
  const Sentence(this.text, this.start, this.end);
}

const _enders = '.!?\u2026\u3002\uFF01\uFF1F';
const _closers = '"\'\u201D\u2019)]';

const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc', 'inc',
  'ltd', 'co', 'no', 'vol', 'fig', 'mt', 'gen', 'col', 'capt', 'lt', 'sgt',
};

bool _isLetter(int u) => (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
bool _isDigit(int u) => u >= 48 && u <= 57;

bool _isFalseEnd(String t, int i) {
  if (t[i] != '.') return false;
  // decimals: 3.5
  if (i > 0 &&
      i + 1 < t.length &&
      _isDigit(t.codeUnitAt(i - 1)) &&
      _isDigit(t.codeUnitAt(i + 1))) {
    return true;
  }
  // word before the dot
  int s = i;
  while (s > 0 && _isLetter(t.codeUnitAt(s - 1))) {
    s--;
  }
  final word = t.substring(s, i);
  if (word.isEmpty) return false;
  if (word.length == 1) return true; // initials, "e.g."
  return _abbreviations.contains(word.toLowerCase());
}

List<Sentence> splitSentences(String text) {
  final out = <Sentence>[];
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    if (!_enders.contains(text[i])) continue;
    // "..." or "?!" -> only split on the last one
    if (i + 1 < text.length && _enders.contains(text[i + 1])) continue;
    if (_isFalseEnd(text, i)) continue;
    int j = i + 1;
    while (j < text.length && _closers.contains(text[j])) {
      j++;
    }
    final chunk = text.substring(start, j);
    if (chunk.trim().isNotEmpty) out.add(Sentence(chunk, start, j));
    start = j;
    i = j - 1;
  }
  if (start < text.length) {
    final chunk = text.substring(start);
    if (chunk.trim().isNotEmpty) out.add(Sentence(chunk, start, text.length));
  }
  return out;
}
