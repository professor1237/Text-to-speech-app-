import 'package:floating_window_android/floating_window_android.dart';

class FloatingWindowService {
  static Future<void> showFloatingPlayer() async {
    final granted = await FloatingWindowAndroid.isPermissionGranted();
    if (!granted) {
      await FloatingWindowAndroid.requestPermission();
      return;
    }
    await FloatingWindowAndroid.showOverlay(
      width: WindowSize.matchParent,
      height: 120,
      alignment: OverlayAlignment.top,
      enableDrag: true,
      overlayTitle: "T2S Reader Player",
    );
  }
}
