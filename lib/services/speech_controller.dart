import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';

class SentenceRef {
  final int block;
  final Sentence sentence;
  const SentenceRef(this.block, this.sentence);
}

class SpeechController extends ChangeNotifier {
  final FlutterTts tts = FlutterTts();
  List<SentenceRef> _queue = [];
  int _index = -1;
  bool _cancelled = false;
  bool _ready = false;

  SentenceRef? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isSpeaking => _index >= 0;

  Future<void> _init() async {
    if (_ready) return;
    await tts.awaitSpeakCompletion(true);
    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.0);
    _ready = true;
  }

  Future<void> speak(
      List<SentenceRef> queue, int start, List<TermRule> rules) async {
    await _init();
    await _cancel();
    _cancelled = false;
    _queue = queue;

    for (int i = start; i < queue.length; i++) {
      if (_cancelled) return;
      _index = i;
      notifyListeners();
      final text = applyTermRules(queue[i].sentence.text, rules);
      if (text.trim().isEmpty) continue;
      await tts.speak(text);
    }
    if (!_cancelled) {
      _index = -1;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _cancel();
    _index = -1;
    notifyListeners();
  }

  Future<void> _cancel() async {
    _cancelled = true;
    try {
      await tts.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }
}
