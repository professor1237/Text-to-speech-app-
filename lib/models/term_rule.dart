import 'dart:convert';

class TermRule {
  final String find;
  final String replace;
  final bool regex;
  final bool caseSensitive;
  final bool enabled;

  const TermRule({
    required this.find,
    required this.replace,
    this.regex = false,
    this.caseSensitive = true,
    this.enabled = true,
  });

  TermRule copyWith({
    String? find,
    String? replace,
    bool? regex,
    bool? caseSensitive,
    bool? enabled,
  }) =>
      TermRule(
        find: find ?? this.find,
        replace: replace ?? this.replace,
        regex: regex ?? this.regex,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'find': find,
        'replace': replace,
        'regex': regex,
        'caseSensitive': caseSensitive,
        'enabled': enabled,
      };

  factory TermRule.fromJson(Map<String, dynamic> j) => TermRule(
        find: j['find'] ?? '',
        replace: j['replace'] ?? '',
        regex: j['regex'] ?? false,
        caseSensitive: j['caseSensitive'] ?? true,
        enabled: j['enabled'] ?? true,
      );
}

String applyTermRules(String input, List<TermRule> rules) {
  var out = input;
  for (final r in rules) {
    if (!r.enabled || r.find.isEmpty) continue;
    final pattern = r.regex
        ? RegExp(r.find, caseSensitive: r.caseSensitive)
        : RegExp(RegExp.escape(r.find), caseSensitive: r.caseSensitive);
    out = out.replaceAll(pattern, r.replace);
  }
  return out;
}

List<TermRule> decodeRules(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  final list = jsonDecode(raw) as List;
  return list.map((e) => TermRule.fromJson(e as Map<String, dynamic>)).toList();
}

String encodeRules(List<TermRule> rules) =>
    jsonEncode(rules.map((e) => e.toJson()).toList());
