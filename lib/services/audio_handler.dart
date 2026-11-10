import 'package:audio_service/audio_service.dart';
import 'speech_controller.dart';

class TtsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  @override
  Future<void> play() async {
    // Set the notification to show "Playing"
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: true,
    ));
    SpeechController.instance.resume();
  }

  @override
  Future<void> pause() async {
    await SpeechController.instance.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.ready,
      playing: false,
    ));
  }

  @override
  Future<void> stop() async {
    await SpeechController.instance.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}
