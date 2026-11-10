import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static final fontScale = ValueNotifier<double>(1.0);
  static final seedColor = ValueNotifier<Color>(Colors.indigo);

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
    final v = s.clamp(0.7, 2.0);
    fontScale.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', v);
  }

  static Future<void> setSeedColor(String name) async {
    seedColor.value = seedChoices[name] ?? Colors.indigo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seed_color', name);
  }
}
