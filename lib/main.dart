import 'package:flutter/material.dart';
import 'services/settings_service.dart';
import 'screens/library_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.load();
  runApp(const T2SApp());
}

class T2SApp extends StatelessWidget {
  const T2SApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService.themeMode,
      builder: (_, mode, __) => ValueListenableBuilder<Color>(
        valueListenable: SettingsService.seedColor,
        builder: (context, seed, _) => MaterialApp(
          title: 'T2S Reader',
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
