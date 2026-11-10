class Sentence {
  final String text;
  final int start;
  final int end;
  const Sentence(this.text, this.start, this.end);
}

const _enders = '.!?\u2026\u3002\uFF01\uFF1F';
const _closers = '"\'\u201D\u2019)]';

List<Sentence> splitSentences(String text) {
  final out = <Sentence>[];
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    if (!_enders.contains(text[i])) continue;
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
