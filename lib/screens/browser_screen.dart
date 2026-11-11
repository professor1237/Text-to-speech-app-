import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart' show audioHandler;
import '../models/term_rule.dart';
import '../services/speech_controller.dart';
import '../services/web_reader_service.dart';
import 'terms_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  final _urlController = TextEditingController();
  final _speech = SpeechController.instance;

  bool _loading = false;
  bool _autoRead = false;
  bool _pageReadDone = false;
  bool _pageReady = false;
  String? _currentUrl;
  List<TermRule> _rules = [];
  String _lastHighlightKey = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _loading = true;
            _pageReady = false;
            _pageReadDone = false;
            _currentUrl = url;
            _urlController.text = url;
          });
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _pageReady = true;
          });
          if (_autoRead && !_pageReadDone) {
            _pageReadDone = true;
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) _readPage();
          }
        },
      ))
      ..loadRequest(Uri.parse('https://duckduckgo.com/'));
    _speech.addListener(_onSpeechChanged);
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    _rules = decodeRules(prefs.getString('term_rules'));
    _speech.setRules(_rules);
  }

  void _onSpeechChanged() {
    if (!mounted) return;
    final cur = _speech.current;
    if (cur != null && _speech.owner == _currentUrl) {
      final key = '${cur.block}:${cur.sentence.start}';
      if (key != _lastHighlightKey) {
        _lastHighlightKey = key;
        _highlight(cur.sentence.text);
      }
    }
    setState(() {});
  }

  Future<void> _highlight(String sentence) async {
    final safe = sentence
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    final js = '''
      (function() {
        try {
          var t = '$safe'.trim();
          if (!t || !window.find) return;
          window.getSelection().removeAllRanges();
          window.find(t, false, false, true, false, false, false);
        } catch (e) {}
      })();
    ''';
    try { await _controller.runJavaScript(js); } catch (_) {}
  }

  String _extractString(Object raw) {
    if (raw is String) {
      try {
        final v = jsonDecode(raw);
        return v is String ? v : v.toString();
      } catch (_) {
        return raw;
      }
    }
    return raw.toString();
  }

  Future<void> _readPage() async {
    if (!_pageReady || _currentUrl == null) {
      _snack('Wait for the page to finish loading.');
      return;
    }
    final url = _currentUrl!;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
          WebReaderService.extractScript);
      final queue = WebReaderService.buildQueue(_extractString(raw));
      if (queue.isEmpty) {
        _snack('No readable text found on this page.');
        return;
      }
      String title = url;
      try {
        final t = await _controller.runJavaScriptReturningResult('document.title');
        final ts = _extractString(t).trim();
        if (ts.isNotEmpty) title = ts;
      } catch (_) {}
      audioHandler.updateMediaItem(MediaItem(
        id: url,
        title: title,
        artist: Uri.parse(url).host,
      ));
      _speech.setRules(_rules);
      await _speech.speak(queue, 0, _rules, owner: url);
      _snack('Reading ${queue.length} sentences');
    } catch (e) {
      _snack('Could not read this page: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _navigate(String input) {
    final q = input.trim();
    if (q.isEmpty) return;
    Uri? uri;
    if (q.contains('://')) {
      uri = Uri.tryParse(q);
    } else if (q.contains('.') && !q.contains(' ')) {
      uri = Uri.tryParse('https://$q');
    }
    if (uri == null || uri.host.isEmpty) {
      uri = Uri.parse('https://duckduckgo.com/?q=${Uri.encodeComponent(q)}');
    }
    _controller.loadRequest(uri);
  }

  Future<void> _openTerms() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => TermsScreen(rules: _rules)));
    await _loadRules();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeechChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active  = _speech.isActive && _speech.owner == _currentUrl;
    final playing = active && _speech.isPlaying;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: _navigate,
          decoration: const InputDecoration(
            hintText: 'Search or type a web address',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_autoRead ? Icons.volume_up : Icons.volume_off),
            tooltip: _autoRead ? 'Auto-read: ON' : 'Auto-read: OFF',
            onPressed: () => setState(() => _autoRead = !_autoRead),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Term replacement',
            onPressed: _openTerms,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () async {
                      if (await _controller.canGoBack()) _controller.goBack();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () async {
                      if (await _controller.canGoForward()) _controller.goForward();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _controller.reload(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.record_voice_over),
                    tooltip: 'Read this page',
                    onPressed: _readPage,
                  ),
                  IconButton(
                    icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                    iconSize: 40,
                    tooltip: playing ? 'Pause' : 'Play',
                    onPressed: () {
                      if (active) {
                        playing ? _speech.pause() : _speech.resume();
                      } else {
                        _readPage();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_circle),
                    tooltip: 'Stop',
                    onPressed: active ? () => _speech.stop() : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
