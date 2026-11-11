import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart' show audioHandler;
import '../models/term_rule.dart';
import '../services/book_parser.dart';
import '../services/library_db.dart';
import '../services/speech_controller.dart';
import '../services/web_reader_service.dart';
import 'terms_screen.dart';
import 'voice_sheet.dart';

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

  /// The page that is being read aloud. Kept apart from [_currentUrl] so the
  /// Pause / Stop buttons still work after you open another page.
  String? _readOwner;
  int _lastIndex = -1;
  List<TermRule> _rules = [];
  String _lastHighlightKey = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          const ok = {'http', 'https', 'about', 'data', 'blob'};
          if (u != null && ok.contains(u.scheme)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent; // intent://, market:// ...
        },
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
        onUrlChange: (change) {
          final url = change.url;
          if (!mounted || url == null) return;
          setState(() {
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
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) {
            if (mounted) setState(() => _loading = false);
            _snack('Could not load the page: ${e.description}');
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
    if (cur != null && _readOwner != null && _speech.owner == _readOwner) {
      final key = '${cur.block}:${cur.sentence.start}';
      if (key != _lastHighlightKey) {
        _lastHighlightKey = key;
        final back = _speech.index < _lastIndex;
        _lastIndex = _speech.index;
        _highlight(cur.sentence.text, back);
      }
    }
    setState(() {});
  }

  /// Selects the sentence on the page (this also scrolls it into view).
  Future<void> _highlight(String sentence, bool backwards) async {
    final js = '''
      (function(t, back) {
        try {
          t = (t || '').replace(/\\s+/g, ' ').trim();
          if (!t || !window.find) return;
          var ok = window.find(t, false, back, true, false, false, false);
          if (!ok && t.length > 60) {
            // long sentence split across tags: find its beginning
            window.find(t.substring(0, 60), false, back, true, false, false, false);
          }
        } catch (e) {}
      })(${jsonEncode(sentence)}, $backwards);
    ''';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
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
      final raw = await _controller
          .runJavaScriptReturningResult(WebReaderService.extractScript);
      final queue = WebReaderService.buildQueue(_extractString(raw));
      if (queue.isEmpty) {
        _snack('No readable text found on this page.');
        return;
      }
      String title = url;
      try {
        final t =
            await _controller.runJavaScriptReturningResult('document.title');
        final ts = _extractString(t).trim();
        if (ts.isNotEmpty) title = ts;
      } catch (_) {}
      audioHandler.updateMediaItem(MediaItem(
        id: url,
        title: title,
        artist: Uri.parse(url).host,
      ));
      _readOwner = url;
      _lastIndex = -1;
      _lastHighlightKey = '';
      _speech.setRules(_rules);
      await _speech.speak(queue, 0, _rules, owner: url);
    } catch (e) {
      _snack('Could not read this page: $e');
    }
  }

  /// Saves the open page into the library so it can be read later.
  Future<void> _saveToLibrary() async {
    if (!_pageReady || _currentUrl == null) {
      _snack('Wait for the page to finish loading.');
      return;
    }
    try {
      final raw = await _controller
          .runJavaScriptReturningResult('document.documentElement.outerHTML');
      final bytes = Uint8List.fromList(utf8.encode(_extractString(raw)));
      final host = Uri.parse(_currentUrl!).host;
      final book = await compute(
        BookParser.parse,
        BookInput('page.html', bytes, host),
      );
      final title = (book.title.trim().isEmpty || book.title == 'Untitled')
          ? host
          : book.title;
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'book_${DateTime.now().millisecondsSinceEpoch}.html');
      await File(dest).writeAsBytes(bytes);
      await LibraryDB.insert(dest, title, host, null);
      _snack('Saved to your library');
    } catch (e) {
      _snack('Could not save this page: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _navigate(String input) {
    FocusScope.of(context).unfocus();
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

  void _openVoice() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const VoiceSheet(),
    );
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeechChanged);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active =
        _speech.isActive && _readOwner != null && _speech.owner == _readOwner;
    final playing = active && _speech.isPlaying;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Back goes to the previous web page first, then leaves the browser.
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'save':
                    _saveToLibrary();
                  case 'voice':
                    _openVoice();
                  case 'terms':
                    _openTerms();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'save', child: Text('Save to library')),
                PopupMenuItem(
                    value: 'voice', child: Text('Voice and sleep timer')),
                PopupMenuItem(value: 'terms', child: Text('Term replacement')),
              ],
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () async {
                        if (await _controller.canGoBack()) {
                          _controller.goBack();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () async {
                        if (await _controller.canGoForward()) {
                          _controller.goForward();
                        }
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
                      icon:
                          Icon(playing ? Icons.pause_circle : Icons.play_circle),
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
      ),
    );
  }
}
