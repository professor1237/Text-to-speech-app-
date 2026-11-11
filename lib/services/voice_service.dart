import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceInfo {
  final String name;
  final String locale;
  const VoiceInfo(this.name, this.locale);
}

/// Pitch, voice and speech engine choices (saved between launches).
class VoiceService {
  static const _kPitch = 'tts_pitch';
  static const _kVoiceName = 'tts_voice_name';
  static const _kVoiceLocale = 'tts_voice_locale';
  static const _kEngine = 'tts_engine';

  static Future<double> savedPitch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kPitch) ?? 1.0;
  }

  static Future<String?> savedEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEngine);
  }

  static Future<String?> savedVoiceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVoiceName);
  }

  /// Applies saved settings. A failure is ignored so speech still works.
  static Future<void> applySaved(FlutterTts tts) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final engine = prefs.getString(_kEngine);
      if (engine != null) await tts.setEngine(engine);
    } catch (_) {}
    try {
      final name = prefs.getString(_kVoiceName);
      final locale = prefs.getString(_kVoiceLocale);
      if (name != null && locale != null) {
        await tts.setVoice({'name': name, 'locale': locale});
      }
    } catch (_) {}
    try {
      await tts.setPitch(prefs.getDouble(_kPitch) ?? 1.0);
    } catch (_) {}
  }

  static Future<void> savePitch(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPitch, v);
  }

  static Future<void> saveEngine(String? engine) async {
    final prefs = await SharedPreferences.getInstance();
    if (engine == null) {
      await prefs.remove(_kEngine);
    } else {
      await prefs.setString(_kEngine, engine);
    }
    // A voice belongs to one engine, so forget the old one.
    await prefs.remove(_kVoiceName);
    await prefs.remove(_kVoiceLocale);
  }

  static Future<void> saveVoice(VoiceInfo? v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_kVoiceName);
      await prefs.remove(_kVoiceLocale);
    } else {
      await prefs.setString(_kVoiceName, v.name);
      await prefs.setString(_kVoiceLocale, v.locale);
    }
  }

  static Future<List<String>> engines(FlutterTts tts) async {
    try {
      final raw = await tts.getEngines;
      return (raw as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<VoiceInfo>> voices(FlutterTts tts) async {
    try {
      final raw = await tts.getVoices;
      final out = <VoiceInfo>[];
      for (final v in (raw as List)) {
        if (v is Map) {
          final name = v['name']?.toString();
          final locale = v['locale']?.toString();
          if (name != null && locale != null) out.add(VoiceInfo(name, locale));
        }
      }
      out.sort((a, b) => a.locale == b.locale
          ? a.name.compareTo(b.name)
          : a.locale.compareTo(b.locale));
      return out;
    } catch (_) {
      return [];
    }
  }
}
