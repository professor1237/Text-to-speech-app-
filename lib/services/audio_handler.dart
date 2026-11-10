import 'package:audio_service/audio_service.dart';
import 'speech_controller.dart';

class TtsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  TtsAudioHandler() {
    SpeechController.instance.onStateChanged = _sync;
  }

  void _sync(SpeechState s) {
    final playing = s == SpeechState.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: s == SpeechState.stopped
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      playing: playing,
    ));
  }

  @override
  Future<void> play() => SpeechController.instance.resume();

  @override
  Future<void> pause() => SpeechController.instance.pause();

  @override
  Future<void> stop() => SpeechController.instance.stop();

  @override
  Future<void> skipToNext() => SpeechController.instance.skipNext();

  @override
  Future<void> skipToPrevious() => SpeechController.instance.skipPrev();
}
