import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // global audioHandler
import '../models/block.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';
import '../services/book_parser.dart';
import '../services/epub_service.dart';
import '../services/settings_service.dart';
import '../services/speech_controller.dart';
import '../widgets/paragraph_view.dart';
import 'settings_sheet.dart';
import 'terms_screen.dart';

/// What the background worker needs.
class _LoadRequest {
  final String path;
  final String title;
  const _LoadRequest(this.path, this.title);
}

/// Result of loading a book in the background.
class _LoadedBook {
  final BookContent book;
  final List<SentenceRef> queue;
  _LoadedBook(this.book, this.queue);
}

/// Runs in a background isolate: read file, parse it, split sentences.
Future<_LoadedBook> _loadBookInBackground(_LoadRequest req) async {
  final bytes = await File(req.path).readAsBytes();
  final book = await BookParser.parse(BookInput(req.path, bytes, req.title));
  final q = <SentenceRef>[];
  for (int c = 0; c < book.chapters.length; c++) {
    final blocks = book.chapters[c].blocks;
    for (int b = 0; b < blocks.length; b++) {
      for (final s in splitSentences(blocks[b].text)) {
        q.add(SentenceRef(c, b, s));
      }
    }
  }
  return _LoadedBook(book, q);
}

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String title;
  const ReaderScreen({super.key, required this.filePath, required this.title});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _speech = SpeechController.instance;
  final _itemScroll = ItemScrollController();

  BookContent? _book;
  List<SentenceRef> _queue = [];
  List<TermRule> _rules = [];
  int _chapter = 0;
  int _startIndex = 0; // where Play begins / last reading position
  int _lastChapter = -1;
  int _lastBlock = -1;
  String? _error;
  double _speed = 0.5;

  String get _posKey => 'pos_${widget.filePath}';

  @override
  void initState() {
    super.initState();
    // Opening a different book resets playback of the old one.
    if (_speech.owner != widget.filePath) _speech.stop();
    _speech.addListener(_onSpeechChanged);
    SettingsService.fontScale.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeechChanged);
    SettingsService.fontScale.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  // ---------- loading ----------

  Future<void> _load() async {
    try {
      // Heavy work runs in the background so the app never freezes.
      final loaded = await compute(
        _loadBookInBackground,
        _LoadRequest(widget.filePath, widget.title),
      );
      final book = loaded.book;
      final queue = loaded.queue;
      if (book.chapters.isEmpty) {
        throw Exception('No readable text found in this book.');
      }
      final prefs = await SharedPreferences.getInstance();
      final rules = decodeRules(prefs.getString('term_rules'));

      var start = prefs.getInt(_posKey) ?? 0;
      if (_speech.owner == widget.filePath && _speech.index >= 0) {
        start = _speech.index; // re-opened while still speaking
      }
      if (start < 0 || start >= queue.length) start = 0;

      _speech.setRules(rules);
      if (!mounted) return;
      setState(() {
        _book = book;
        _queue = queue;
        _rules = rules;
        _startIndex = start;
        _chapter = queue.isEmpty ? 0 : queue[start].chapter;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_posKey, _startIndex);
  }

  // ---------- speech ----------

  String _chapterTitle(int i) {
    final t = _book!.chapters[i].title.trim();
    return t.isEmpty ? 'Chapter ${i + 1}' : t;
  }

  void _updateMediaItem(int chapter) {
    audioHandler.updateMediaItem(MediaItem(
      id: widget.filePath,
      album: _book!.author,
      title: _book!.title,
      artist: _chapterTitle(chapter),
    ));
  }

  void _onSpeechChanged() {
    if (!mounted || _book == null) return;
    final cur = _speech.current;
    if (cur != null && _speech.owner == widget.filePath) {
      _startIndex = _speech.index;
      _savePosition();
      if (cur.chapter != _chapter) {
        setState(() => _chapter = cur.chapter);
        _updateMediaItem(cur.chapter);
      }
      _followBlock(cur.chapter, cur.block);
    }
    setState(() {});
  }

  void _followBlock(int chapter, int block) {
    if (chapter == _lastChapter && block == _lastBlock) return;
    _lastChapter = chapter;
    _lastBlock = block;
    _scrollToBlock(block, 3);
  }

  void _scrollToBlock(int block, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_itemScroll.isAttached) {
        _itemScroll.scrollTo(
          index: block,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (tries > 0) {
        _scrollToBlock(block, tries - 1);
      }
    });
  }

  void _playFrom(int index) {
    if (_book == null || _queue.isEmpty) return;
    if (index < 0 || index >= _queue.length) index = 0;
    _startIndex = index;
    _updateMediaItem(_queue[index].chapter);
    _speech.speak(_queue, index, _rules, owner: widget.filePath);
  }

  int _startForCurrentChapter() {
    if (_startIndex >= 0 &&
        _startIndex < _queue.length &&
        _queue[_startIndex].chapter == _chapter) {
      return _startIndex;
    }
    final i = _queue.indexWhere((s) => s.chapter == _chapter);
    return i < 0 ? 0 : i;
  }

  void _togglePlay() {
    if (_speech.state == SpeechState.playing) {
      _speech.pause();
    } else if (_speech.state == SpeechState.paused &&
        _speech.owner == widget.filePath) {
      _speech.resume();
    } else {
      _playFrom(_startForCurrentChapter());
    }
  }

  void _onDoubleTap(int blockIdx, int charIdx) {
    int target = -1;
    for (int i = 0; i < _queue.length; i++) {
      final r = _queue[i];
      if (r.chapter != _chapter) {
        if (target >= 0) break; // already passed our chapter
        continue;
      }
      if (r.block > blockIdx) break;
      if (r.block == blockIdx && r.sentence.start <= charIdx) target = i;
    }
    if (target >= 0) _playFrom(target);
  }

  Future<void> _openTerms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TermsScreen(rules: _rules)),
    );
    final prefs = await SharedPreferences.getInstance();
    final rules = decodeRules(prefs.getString('term_rules'));
    _speech.setRules(rules);
    if (mounted) setState(() => _rules = rules);
  }

  // ---------- UI ----------

  TextStyle _styleFor(BlockType t) {
    final scale = SettingsService.fontScale.value;
    final base = TextStyle(fontSize: 18 * scale, height: 1.55);
    switch (t) {
      case BlockType.heading:
        return base.copyWith(fontSize: 22 * scale, fontWeight: FontWeight.bold);
      case BlockType.quote:
        return base.copyWith(fontStyle: FontStyle.italic);
      case BlockType.listItem:
      case BlockType.paragraph:
        return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _speech.isActive;
    final playing = _speech.isPlaying;
    return Scaffold(
      appBar: AppBar(
        title: Text(_book == null ? widget.title : _chapterTitle(_chapter)),
        actions: [
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
                    _chapterTitle(i),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: i == _chapter,
                  onTap: () {
                    _speech.stop();
                    final first = _queue.indexWhere((s) => s.chapter == i);
                    setState(() {
                      _chapter = i;
                      _startIndex = first < 0 ? 0 : first;
                      _lastChapter = -1;
                      _lastBlock = -1;
                    });
                    _savePosition();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
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
                          onPressed: active ? () => _speech.skipPrev() : null,
                        ),
                        IconButton(
                          icon: Icon(
                              playing ? Icons.pause_circle : Icons.play_circle),
                          iconSize: 40,
                          tooltip: playing ? 'Pause' : 'Play',
                          onPressed: _togglePlay,
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop_circle),
                          iconSize: 40,
                          tooltip: 'Stop',
                          onPressed: active ? () => _speech.stop() : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          iconSize: 32,
                          tooltip: 'Next sentence',
                          onPressed: active ? () => _speech.skipNext() : null,
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
    final cur = _speech.owner == widget.filePath ? _speech.current : null;

    int initial = 0;
    if (_startIndex >= 0 &&
        _startIndex < _queue.length &&
        _queue[_startIndex].chapter == _chapter) {
      initial = _queue[_startIndex].block;
    }
    if (initial >= chapter.blocks.length) initial = 0;

    return ScrollablePositionedList.builder(
      key: ValueKey(_chapter),
      itemScrollController: _itemScroll,
      initialScrollIndex: initial,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: chapter.blocks.length,
      itemBuilder: (_, i) {
        final block = chapter.blocks[i];
        int? hs, he;
        if (cur != null && cur.chapter == _chapter && cur.block == i) {
          hs = cur.sentence.start;
          he = cur.sentence.end;
        }
        return ParagraphView(
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
