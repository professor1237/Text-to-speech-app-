import 'dart:convert';
import 'package:http/http.dart' as http;

String decodeHtmlResponse(http.Response response) {
  final bytes = response.bodyBytes;
  final type = response.headers['content-type'] ?? '';
  var charset = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
      .firstMatch(type)
      ?.group(1)
      ?.replaceAll('"', '')
      .replaceAll("'", '')
      .toLowerCase();
  charset ??= _sniffMetaCharset(bytes);
  if (charset == 'iso-8859-1' || charset == 'latin1' || charset == 'windows-1252') {
    return latin1.decode(bytes, allowInvalid: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _sniffMetaCharset(List<int> bytes) {
  final head = latin1.decode(
    bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
    allowInvalid: true,
  );
  return RegExp(r'''<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_\-]+)''', caseSensitive: false)
      .firstMatch(head)
      ?.group(1)
      ?.toLowerCase();
}