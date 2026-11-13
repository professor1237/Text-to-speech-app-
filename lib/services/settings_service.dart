import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static final fontScale = ValueNotifier<double>(1.0);
  static final seedColor = ValueNotifier<Color>(Colors.indigo);
  static final readerTextColor = ValueNotifier<Color>(const Color(0xFF212121));
  static final settingsPanelBackgroundColor = ValueNotifier<Color>(Colors.white);

  static const seedChoices = <String, Color>{
    'Indigo': Colors.indigo,
    'Teal': Colors.teal,
    'Purple': Colors.purple,
    'Orange': Colors.orange,
    'Green': Colors.green,
    'Blue': Colors.blue,
    'Pink': Colors.pink,
    'Red': Colors.red,
  };

  static const readerTextChoices = <String, Color>{
    'Dark': Color(0xFF212121),
    'Black': Colors.black,
    'Grey': Color(0xFF616161),
    'White': Colors.white,
    'Cream': Color(0xFF5D4037),
    'Navy': Color(0xFF102A43),
  };

  static const settingsPanelBackgroundChoices = <String, Color>{
    'White': Colors.white,
    'Warm': Color(0xFFFFF8E7),
    'Sepia': Color(0xFFF1E3C8),
    'Light grey': Color(0xFFF1F3F5),
    'Dark': Color(0xFF171717),
    'Black': Colors.black,
    'Navy': Color(0xFF102A43),
  };

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final m = prefs.getString('theme_mode') ?? 'system';
    themeMode.value = switch (m) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    fontScale.value = prefs.getDouble('font_scale') ?? 1.0;
    final name = prefs.getString('seed_color') ?? 'Indigo';
    seedColor.value = seedChoices[name] ?? Colors.indigo;
    readerTextColor.value =
        Color(prefs.getInt('reader_text_color') ?? 0xFF212121);
    settingsPanelBackgroundColor.value =
        Color(prefs.getInt('reader_background_color') ?? 0xFFFFFFFF);
  }

  static Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  static Future<void> setFontScale(double s) async {
    final v = s.clamp(0.7, 2.0).toDouble();
    fontScale.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', v);
  }

  static Future<void> setSeedColor(String name) async {
    seedColor.value = seedChoices[name] ?? Colors.indigo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seed_color', name);
  }

  static Future<void> setReaderTextColor(Color color) async {
    readerTextColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_text_color', color.value);
  }

  static Future<void> setSettingsPanelBackgroundColor(Color color) async {
    settingsPanelBackgroundColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_background_color', color.toARGB32());
  }
}
