import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const _rateKey = 'speech_rate';
  static const _maxTtsChunkLength = 3500;

  final FlutterTts tts = FlutterTts();

  List<SentenceRef> _queue = [];
  List<TermRule> _rules = [];
  int _index = -1;
  int _generation = 0;
  bool _ready = false;
  bool _audioSessionConfigured = false;
  Future<void>? _initializing;
  double _rate = 0.5;
  SpeechState _state = SpeechState.stopped;

  /// Which book (file path) the current queue belongs to.
  String? owner;

  /// Lets the notification (audio_handler) follow our state.
  void Function(SpeechState state)? onStateChanged;
  void Function(SentenceRef? current)? onCurrentChanged;
  String? mediaTitle;
  String mediaAuthor = 'Unknown';
  List<String> chapterTitles = const [];

  /// Reports a sentence-level playback error instead of silently skipping it.
  void Function(String message)? onPlaybackError;
  String? lastError;

  int get index => _index;
  double get rate => _rate;
  SpeechState get state => _state;
  bool get isActive => _state != SpeechState.stopped;
  bool get isPlaying => _state == SpeechState.playing;
  SentenceRef? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  Future<void> initialize() => _init();

  Future<void> _init() {
    if (_ready) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _configureAudioSession();
      final prefs = await SharedPreferences.getInstance();
      _rate = (prefs.getDouble(_rateKey) ?? 0.5).clamp(0.1, 2.0);
      await tts.awaitSpeakCompletion(true);
      await tts.setSpeechRate(_rate);
      await VoiceService.applySaved(tts);
      _ready = true;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _configureAudioSession() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      session.interruptionEventStream.listen((event) {
        if (event.begin && isPlaying) pause();
      });
      session.becomingNoisyEventStream.listen((_) {
        if (isPlaying) pause();
      });
      _audioSessionConfigured = true;
    } catch (e) {
      // Audio focus is best-effort; a platform-specific session failure must
      // not prevent the text-to-speech engine from initializing.
      debugPrint('Could not configure audio session: $e');
    }
  }

  Future<void> _activateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('Could not activate audio session: $e');
    }
  }

  Future<void> _deactivateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      debugPrint('Could not deactivate audio session: $e');
    }
  }

  void _setState(SpeechState s) {
    _state = s;
    onStateChanged?.call(s);
    notifyListeners();
  }

  void setRules(List<TermRule> rules) => _rules = rules;

  void setBookMetadata(String title, String author, List<String> chapters) {
    mediaTitle = title;
    mediaAuthor = author;
    chapterTitles = chapters;
  }

  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.1, 2.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rateKey, _rate);
    await _init();
    await tts.setSpeechRate(_rate);
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    final v = pitch.clamp(0.5, 2.0);
    await VoiceService.savePitch(v);
    try {
      await tts.setPitch(v);
    } catch (_) {}
  }

  Future<void> changeEngine(String? engine) async {
    await stop();
    await VoiceService.saveEngine(engine);
    try {
      if (engine != null) await tts.setEngine(engine);
      await tts.setSpeechRate(_rate);
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

  Future<void> _savePosition() async {
    final path = owner;
    if (path == null || _index < 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pos_$path', _index);
    } catch (e) {
      debugPrint('Could not save reading position: $e');
    }
  }

  void _reportPlaybackError(String message) {
    lastError = message;
    onPlaybackError?.call(message);
    notifyListeners();
  }

  Future<void> speak(
    List<SentenceRef> queue,
    int start,
    List<TermRule> rules, {
    String? owner,
  }) async {
    final gen = ++_generation;
    try {
      await _init();
    } catch (e) {
      if (gen == _generation) {
        _index = -1;
        _reportPlaybackError('Speech engine could not initialize: $e');
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

    lastError = null;
    await _activateAudioSession();
    _queue = queue;
    _rules = rules;
    if (owner != null) this.owner = owner;
    _index = start;
    await _savePosition();
    _setState(SpeechState.playing);
    await _run(gen);
  }

  /// Splits text at word boundaries so Android TTS never receives an
  /// oversized utterance. The source sentence remains one queue item.
  List<String> _ttsChunks(String text) {
    final chunks = <String>[];
    var remaining = text.trim();
    while (remaining.length > _maxTtsChunkLength) {
      var cut = remaining.lastIndexOf(' ', _maxTtsChunkLength);
      if (cut < _maxTtsChunkLength ~/ 2) cut = _maxTtsChunkLength;
      // Avoid splitting a UTF-16 surrogate pair.
      if (cut > 0 && cut < remaining.length) {
        final unit = remaining.codeUnitAt(cut - 1);
        if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
      }
      chunks.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trimLeft();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  Future<void> _run(int gen) async {
    while (gen == _generation && _index >= 0 && _index < _queue.length) {
      notifyListeners();
      onCurrentChanged?.call(current);
      await _savePosition();
      final text = applyTermRules(_queue[_index].sentence.text, _rules);
      var failed = false;
      if (text.trim().isNotEmpty) {
        for (final chunk in _ttsChunks(text)) {
          if (gen != _generation) return;
          try {
            final result = await tts.speak(chunk);
            if (result is int && result != 1 ||
                result is bool && !result) {
              _reportPlaybackError(
                'The speech engine rejected a text segment. Try another voice or engine.',
              );
              failed = true;
              break;
            }
          } catch (e) {
            if (gen != _generation) return;
            _reportPlaybackError('Could not speak this text segment: $e');
            failed = true;
            break;
          }
        }
      }
      if (gen != _generation) return;
      if (failed) {
        await _savePosition();
        _setState(SpeechState.stopped);
        await _deactivateAudioSession();
        return;
      }
      _index++;
    }
    if (gen == _generation) {
      _index = -1;
      _savePosition();
      _setState(SpeechState.stopped);
      await _deactivateAudioSession();
    }
  }

  Future<void> pause() async {
    if (_state != SpeechState.playing) return;
    _generation++;
    await _savePosition();
    _setState(SpeechState.paused);
    try {
      await tts.stop();
    } catch (_) {}
    await _deactivateAudioSession();
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
      await _savePosition();
      notifyListeners();
      return;
    }
    await speak(_queue, target, _rules);
  }

  Future<void> skipNext() => skipTo(_index + 1);
  Future<void> skipPrev() => skipTo(_index - 1);

  Future<void> stop() async {
    _generation++;
    await _savePosition();
    try {
      await tts.stop();
    } catch (_) {}
    _index = -1;
    _setState(SpeechState.stopped);
    await _deactivateAudioSession();
  }
}
