import 'dart:async';
import 'package:flutter/foundation.dart';
import 'speech_controller.dart';

/// Pauses reading after a chosen number of minutes.
class SleepTimer {
  static final remaining = ValueNotifier<Duration?>(null);
  static Timer? _timer;

  static bool get isRunning => remaining.value != null;

  static void start(int minutes) {
    cancel();
    remaining.value = Duration(minutes: minutes);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = remaining.value;
      if (left == null) {
        cancel();
        return;
      }
      final next = left - const Duration(seconds: 1);
      if (next.inSeconds <= 0) {
        cancel();
        SpeechController.instance.pause();
      } else {
        remaining.value = next;
      }
    });
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
    remaining.value = null;
  }
}
