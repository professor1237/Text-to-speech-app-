import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _tts = FlutterTts();
  bool _playing = false;

  @override
  Future<void> play() async {
    _playing = true;
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: true,
    ));
    // This is a simplified bridge. In your real app, you'd call _tts.speak() here
    // with the correct text from your reader state.
  }

  @override
  Future<void> pause() async {
    _playing = false;
    await _tts.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: false,
    ));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    await _tts.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}
