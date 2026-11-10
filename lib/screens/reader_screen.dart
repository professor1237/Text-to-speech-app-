import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/block.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';
import '../services/epub_service.dart';
import '../services/settings_service.dart';
import '../services/floating_window_service.dart';
import '../services/speech_controller.dart';
import '../widgets/paragraph_view.dart';
import 'settings_sheet.dart';
import 'terms_screen.dart';

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String title;
  const ReaderScreen(
      {super.key, required this.filePath, required this.title});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _speech = SpeechController();
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  BookContent? _book;
  int _chapter = 0;
  List<TermRule> _rules = [];
  String? _error;
  double _speed = 0.5;

  @override
  void initState() {
    super.initState();
    _speech.addListener(_onSpeechChanged);
    SettingsService.fontScale.addListener(_onSettingsChanged);
    _load();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.filePath).readAsBytes();
      final book = await EpubService.parse(bytes);
      final prefs = await SharedPreferences.getInstance();
      _rules = decodeRules(prefs.getString('term_rules'));
      setState(() => _book = book);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeechChanged);
    SettingsService.fontScale.removeListener(_onSettingsChanged);
    _speech.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSpeechChanged() {
    final cur = _speech.current;
    if (cur != null) {
      final ctx = _keys[cur.block]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.4,
          curve: Curves.easeOut,
        );
      }
    }
    setState(() {});
  }

  // Builds a queue from ALL chapters starting at chapter 0
  List<SentenceRef> _queueForAllChapters() {
    final q = <SentenceRef>[];
    for (int c = 0; c < _book!.chapters.length; c++) {
      for (int b = 0; b < _book!.chapters[c].blocks.length; b++) {
        for (final s in splitSentences(_book!.chapters[c].blocks[b].text)) {
          q.add(SentenceRef(b, s)); // Note: block index is relative to chapter
        }
      }
    }
    return q;
  }

  void _onDoubleTap(int blockIdx, int charIdx) {
    final blocks = _book!.chapters[_chapter].blocks;
    final q = _queueForAllChapters();
    // Find the global index for the tapped sentence
    int target = 0;
    int counter = 0;
    for (int c = 0; c < _book!.chapters.length; c++) {
      for (int b = 0; b < _book!.chapters[c].blocks.length; b++) {
        for (final s in splitSentences(_book!.chapters[c].blocks[b].text)) {
          if (c == _chapter && b == blockIdx && s.start <= charIdx) {
            target = counter;
          }
          counter++;
        }
      }
    }
    _speech.speak(q, target, _rules);
  }

  void _play() {
    if (_book == null) return;
    final q = _queueForAllChapters();
    _speech.speak(q, 0, _rules); // Start from beginning
  }

  Future<void> _openTerms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TermsScreen(rules: _rules)),
    );
    final prefs = await SharedPreferences.getInstance();
    setState(() => _rules = decodeRules(prefs.getString('term_rules')));
  }

  TextStyle _styleFor(BlockType t) {
    final scale = SettingsService.fontScale.value;
    final base = TextStyle(fontSize: 18 * scale, height: 1.55);
    switch (t) {
      case BlockType.heading:
        return base.copyWith(
            fontSize: 22 * scale, fontWeight: FontWeight.bold);
      case BlockType.quote:
        return base.copyWith(fontStyle: FontStyle.italic);
      case BlockType.listItem:
      case BlockType.paragraph:
        return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _speech.isSpeaking;
    return Scaffold(
      appBar: AppBar(
        title: Text(_book == null
            ? widget.title
            : _book!.chapters[_chapter].title.isEmpty
                ? 'Chapter ${_chapter + 1}'
                : _book!.chapters[_chapter].title),
        actions: [
  IconButton(
    icon: const Icon(Icons.picture_in_picture_alt),
    tooltip: 'Floating Player',
    onPressed: () => FloatingWindowService.showFloatingPlayer(),
  ),
  IconButton(
    icon: const Icon(Icons.tune),
    tooltip: 'Term replacement',
    onPressed: _openTerms,
  ),
],
      ),
      drawer: _book == null
          ? null
          : Drawer(
              child: ListView.builder(
                itemCount: _book!.chapters.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(
                    _book!.chapters[i].title.isEmpty
                        ? 'Chapter ${i + 1}'
                        : _book!.chapters[i].title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: i == _chapter,
                  onTap: () {
                    _speech.stop();
                    _keys.clear();
                    setState(() => _chapter = i);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _book == null
              ? const Center(child: CircularProgressIndicator())
              : _buildReader(),
      bottomNavigationBar: _book == null
          ? null
          : SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          iconSize: 32,
                          tooltip: 'Previous sentence',
                          onPressed: speaking ? _speech.skipPrev : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_circle),
                          iconSize: 40,
                          tooltip: 'Play',
                          onPressed: speaking ? null : _play,
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle),
                          iconSize: 40,
                          tooltip: 'Stop',
                          onPressed: speaking ? () => _speech.stop() : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          iconSize: 32,
                          tooltip: 'Next sentence',
                          onPressed: speaking ? _speech.skipNext : null,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 20),
                        Expanded(
                          child: Slider(
                            value: _speed,
                            min: 0.1,
                            max: 2.0,
                            divisions: 19,
                            label: '${(_speed * 100).round()}%',
                            onChanged: (v) {
                              setState(() => _speed = v);
                              _speech.setRate(v);
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.text_decrease),
                          iconSize: 28,
                          tooltip: 'Smaller text',
                          onPressed: () => SettingsService.setFontScale(
                              SettingsService.fontScale.value - 0.1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_increase),
                          iconSize: 28,
                          tooltip: 'Larger text',
                          onPressed: () => SettingsService.setFontScale(
                              SettingsService.fontScale.value + 0.1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.palette),
                          iconSize: 28,
                          tooltip: 'Appearance',
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => const SettingsSheet(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildReader() {
    final chapter = _book!.chapters[_chapter];
    final cur = _speech.current;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: chapter.blocks.length,
      itemBuilder: (_, i) {
        final block = chapter.blocks[i];
        final key = _keys.putIfAbsent(i, () => GlobalKey());
        int? hs, he;
        if (cur != null && cur.block == i) {
          hs = cur.sentence.start;
          he = cur.sentence.end;
        }
        return ParagraphView(
          key: key,
          block: block,
          highlightStart: hs,
          highlightEnd: he,
          onDoubleTapChar: (c) => _onDoubleTap(i, c),
          style: _styleFor(block.type),
        );
      },
    );
  }
}
