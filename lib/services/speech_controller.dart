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
  double _rate = 0.5; // Default speed is 0.5

  SentenceRef? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isSpeaking => _index >= 0;

  Future<void> _init() async {
    if (_ready) return;
    await tts.awaitSpeakCompletion(true);
    await tts.setSpeechRate(_rate);
    await tts.setPitch(1.0);
    _ready = true;
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 2.0); // Android range is 0.0–2.0 [2†L5-L6]
    await tts.setSpeechRate(_rate);
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

  // Skip forward / backward
  void skipNext() {
    if (current != null) {
      _index = (_index + 1).clamp(0, _queue.length - 1);
      notifyListeners();
      tts.stop();
      speak(_queue, _index, []); // Re-start from the new index
    }
  }

  void skipPrev() {
    if (current != null) {
      _index = (_index - 1).clamp(0, _queue.length - 1);
      notifyListeners();
      tts.stop();
      speak(_queue, _index, []);
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
