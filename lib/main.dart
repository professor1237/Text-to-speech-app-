import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/settings_service.dart';
import 'screens/library_screen.dart';
import 'services/audio_handler.dart';

late AudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.load();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());
  audioHandler = await AudioService.init(
    builder: () => TtsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.tts_reader.audio',
      androidNotificationChannelName: 'Tts Playback',
      androidNotificationOngoing: true,
    ),
  );
  Permission.notification.request(); // Android 13+ notification permission
  runApp(const TtsApp());
}

class TtsApp extends StatelessWidget {
  const TtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService.themeMode,
      builder: (_, mode, __) => ValueListenableBuilder<Color>(
        valueListenable: SettingsService.seedColor,
        builder: (context, seed, _) => MaterialApp(
          title: 'Tts',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: seed,
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: seed,
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          themeMode: mode,
          home: const LibraryScreen(),
        ),
      ),
    );
  }
}
