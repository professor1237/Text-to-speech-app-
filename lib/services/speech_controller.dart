import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';

class SentenceRef {
  final int chapter;
  final int block;
  final Sentence sentence;
  const SentenceRef(this.chapter, this.block, this.sentence);
}

enum SpeechState { stopped, playing, paused }

class SpeechController extends ChangeNotifier {
  static final SpeechController instance = SpeechController._();
  SpeechController._();

  final FlutterTts tts = FlutterTts();

  List<SentenceRef> _queue = [];
  List<TermRule> _rules = [];
  int _index = -1;
  int _generation = 0; // bumped on every speak/pause/stop; kills old loops
  bool _ready = false;
  double _rate = 0.5;
  SpeechState _state = SpeechState.stopped;

  /// Which book (file path) the current queue belongs to.
  String? owner;

  /// Lets the notification (audio_handler) follow our state.
  void Function(SpeechState state)? onStateChanged;

  int get index => _index;
  SpeechState get state => _state;
  bool get isActive => _state != SpeechState.stopped;
  bool get isPlaying => _state == SpeechState.playing;
  SentenceRef? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  Future<void> _init() async {
    if (_ready) return;
    await tts.awaitSpeakCompletion(true);
    await tts.setSpeechRate(_rate);
    await tts.setPitch(1.0);
    _ready = true;
  }

  void _setState(SpeechState s) {
    _state = s;
    onStateChanged?.call(s);
    notifyListeners();
  }

  void setRules(List<TermRule> rules) => _rules = rules;

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 2.0);
    await tts.setSpeechRate(_rate);
  }

  Future<void> speak(
    List<SentenceRef> queue,
    int start,
    List<TermRule> rules, {
    String? owner,
  }) async {
    await _init();
    final gen = ++_generation;
    try {
      await tts.stop();
    } catch (_) {}
    if (gen != _generation) return; // a newer call took over
    if (queue.isEmpty || start < 0 || start >= queue.length) return;

    _queue = queue;
    _rules = rules;
    if (owner != null) this.owner = owner;
    _index = start;
    _setState(SpeechState.playing);
    await _run(gen);
  }

  Future<void> _run(int gen) async {
    while (gen == _generation && _index >= 0 && _index < _queue.length) {
      notifyListeners();
      final text = applyTermRules(_queue[_index].sentence.text, _rules);
      if (text.trim().isNotEmpty) {
        try {
          await tts.speak(text);
        } catch (_) {}
      }
      if (gen != _generation) return; // paused / skipped / stopped
      _index++;
    }
    if (gen == _generation) {
      // finished the whole queue naturally
      _index = -1;
      _setState(SpeechState.stopped);
    }
  }

  Future<void> pause() async {
    if (_state != SpeechState.playing) return;
    _generation++;
    _setState(SpeechState.paused); // keeps _index so resume works
    try {
      await tts.stop();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_state != SpeechState.paused || _queue.isEmpty) return;
    await speak(_queue, _index, _rules);
  }

  Future<void> skipTo(int target) async {
    if (_queue.isEmpty || !isActive) return;
    if (target < 0) target = 0;
    if (target >= _queue.length) {
      await stop();
      return;
    }
    if (_state == SpeechState.paused) {
      _index = target;
      notifyListeners();
      return;
    }
    await speak(_queue, target, _rules);
  }

  Future<void> skipNext() => skipTo(_index + 1);
  Future<void> skipPrev() => skipTo(_index - 1);

  Future<void> stop() async {
    _generation++;
    try {
      await tts.stop();
    } catch (_) {}
    _index = -1;
    _setState(SpeechState.stopped);
  }
}
