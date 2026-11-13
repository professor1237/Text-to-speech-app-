import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';
import 'voice_service.dart';

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
  Future<void>? _initializing;
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

  Future<void> _init() {
    if (_ready) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await tts.awaitSpeakCompletion(true);
      await tts.setSpeechRate(_rate);
      await VoiceService.applySaved(tts); // saved pitch, voice and engine
      _ready = true;
    } finally {
      _initializing = null;
    }
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

  Future<void> setPitch(double pitch) async {
    final v = pitch.clamp(0.5, 2.0);
    await VoiceService.savePitch(v);
    try {
      await tts.setPitch(v);
    } catch (_) {}
  }

  /// Switch speech engine. Stops speaking; the next Play uses the new engine.
  Future<void> changeEngine(String? engine) async {
    await stop();
    await VoiceService.saveEngine(engine);
    try {
      if (engine != null) await tts.setEngine(engine);
      await tts.setSpeechRate(_rate); // a new engine starts with defaults
      await tts.setPitch(await VoiceService.savedPitch());
    } catch (_) {}
  }

  Future<void> changeVoice(VoiceInfo? voice) async {
    await VoiceService.saveVoice(voice);
    try {
      if (voice != null) {
        await tts.setVoice({'name': voice.name, 'locale': voice.locale});
      }
    } catch (_) {}
  }

  Future<void> speak(
    List<SentenceRef> queue,
    int start,
    List<TermRule> rules, {
    String? owner,
  }) async {
    // Invalidate older playback before awaiting initialization. Otherwise a
    // Stop pressed during first-time TTS setup could be overtaken by this call.
    final gen = ++_generation;
    try {
      await _init();
    } catch (_) {
      if (gen == _generation) {
        _index = -1;
        _setState(SpeechState.stopped);
      }
      return;
    }
    if (gen != _generation) return;

    try {
      await tts.stop();
    } catch (_) {}
    if (gen != _generation) return;
    if (queue.isEmpty || start < 0 || start >= queue.length) {
      _index = -1;
      _setState(SpeechState.stopped);
      return;
    }

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
