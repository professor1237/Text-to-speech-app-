import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum WebEpubDownloadMode { adaptive, parallel, sequential }

class WebEpubSiteProfile {
  const WebEpubSiteProfile({
    this.mode = WebEpubDownloadMode.adaptive,
    this.maxParallel = 3,
    this.delaySeconds = 0,
    this.retries = 2,
  });

  final WebEpubDownloadMode mode;
  final int maxParallel;
  final int delaySeconds;
  final int retries;

  WebEpubSiteProfile copyWith({
    WebEpubDownloadMode? mode,
    int? maxParallel,
    int? delaySeconds,
    int? retries,
  }) => WebEpubSiteProfile(
    mode: mode ?? this.mode,
    maxParallel: maxParallel ?? this.maxParallel,
    delaySeconds: delaySeconds ?? this.delaySeconds,
    retries: retries ?? this.retries,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'maxParallel': maxParallel,
    'delaySeconds': delaySeconds,
    'retries': retries,
  };

  factory WebEpubSiteProfile.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    return WebEpubSiteProfile(
      mode: WebEpubDownloadMode.values.firstWhere(
        (v) => v.name == modeName,
        orElse: () => WebEpubDownloadMode.adaptive,
      ),
      maxParallel: (json['maxParallel'] as num?)?.toInt().clamp(1, 10) ?? 3,
      delaySeconds: (json['delaySeconds'] as num?)?.toInt().clamp(0, 30) ?? 0,
      retries: (json['retries'] as num?)?.toInt().clamp(0, 5) ?? 2,
    );
  }
}

/// Persistent global defaults and per-host download profiles.
class WebEpubSettingsService {
  static const _globalKey = 'web_epub_global_profile_v1';
  static const _sitesKey = 'web_epub_site_profiles_v1';
  static const _cleanKey = 'web_epub_cleaning_options_v1';

  static WebEpubSiteProfile global = const WebEpubSiteProfile();
  static Map<String, WebEpubSiteProfile> sites = {};
  static Map<String, bool> cleaning = {
    'footnoteReferences': true,
    'footnoteText': false,
    'endnotes': false,
    'advertisements': true,
    'comments': true,
    'authorNotes': false,
    'chapterNavigation': true,
    'promotionalContent': true,
    'duplicateParagraphs': true,
  };

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawGlobal = prefs.getString(_globalKey);
    if (rawGlobal != null) {
      try {
        global = WebEpubSiteProfile.fromJson(
          jsonDecode(rawGlobal) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    final rawSites = prefs.getString(_sitesKey);
    if (rawSites != null) {
      try {
        final decoded = jsonDecode(rawSites) as Map<String, dynamic>;
        sites = decoded.map((host, value) => MapEntry(
          host,
          WebEpubSiteProfile.fromJson(value as Map<String, dynamic>),
        ));
      } catch (_) {}
    }
    final rawCleaning = prefs.getString(_cleanKey);
    if (rawCleaning != null) {
      try {
        cleaning = {
          ...cleaning,
          ...(jsonDecode(rawCleaning) as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value == true)),
        };
      } catch (_) {}
    }
  }

  static WebEpubSiteProfile forUri(Uri uri) =>
      sites[uri.host.toLowerCase()] ?? global;

  static Future<void> saveGlobal(WebEpubSiteProfile value) async {
    global = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalKey, jsonEncode(value.toJson()));
  }

  static Future<void> saveSite(String host, WebEpubSiteProfile value) async {
    final key = host.toLowerCase().trim();
    if (key.isEmpty) return;
    sites[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sitesKey, jsonEncode(
      sites.map((name, profile) => MapEntry(name, profile.toJson())),
    ));
  }

  static Future<void> saveCleaning(String key, bool value) async {
    cleaning[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleanKey, jsonEncode(cleaning));
  }
}
