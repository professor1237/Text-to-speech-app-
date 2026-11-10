import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/block.dart';
import '../models/sentence.dart';
import '../models/term_rule.dart';
import '../services/epub_service.dart';
import '../services/speech_controller.dart';
import '../widgets/paragraph_view.dart';
import 'terms_screen.dart';

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String title;
  const ReaderScreen({super.key, required this.filePath, required this.title});

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

  @override
  void initState() {
    super.initState();
    _speech.addListener(_onSpeechChanged);
    _load();
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

  List<SentenceRef> _queueFor(List<Block> blocks) {
    final q = <SentenceRef>[];
    for (int b = 0; b < blocks.length; b++) {
      for (final s in splitSentences(blocks[b].text)) {
        q.add(SentenceRef(b, s));
      }
    }
    return q;
  }

  void _onDoubleTap(int blockIdx, int charIdx) {
    final blocks = _book!.chapters[_chapter].blocks;
    final q = _queueFor(blocks);
    int target = 0;
    for (int i = 0; i < q.length; i++) {
      final r = q[i];
      if (r.block < blockIdx) {
        target = i;
        continue;
      }
      if (r.block > blockIdx) break;
      if (r.sentence.start <= charIdx) {
        target = i;
      } else {
        break;
      }
    }
    _speech.speak(q, target, _rules);
  }

  void _togglePlay() {
    if (_speech.isSpeaking) {
      _speech.stop();
    } else {
      final blocks = _book!.chapters[_chapter].blocks;
      _speech.speak(_queueFor(blocks), 0, _rules);
    }
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
    const base = TextStyle(fontSize: 18, height: 1.55);
    switch (t) {
      case BlockType.heading:
        return base.copyWith(fontSize: 22, fontWeight: FontWeight.bold);
      case BlockType.quote:
        return base.copyWith(fontStyle: FontStyle.italic);
      case BlockType.listItem:
      case BlockType.paragraph:
        return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_book == null
            ? widget.title
            : _book!.chapters[_chapter].title.isEmpty
                ? 'Chapter ${_chapter + 1}'
                : _book!.chapters[_chapter].title),
        actions: [
          IconButton(
            icon: Icon(_speech.isSpeaking ? Icons.stop : Icons.play_arrow),
            onPressed: _book == null ? null : _togglePlay,
          ),
          IconButton(icon: const Icon(Icons.tune), onPressed: _openTerms),
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
    );
  }

  Widget _buildReader() {
    final chapter = _book!.chapters[_chapter];
    final cur = _speech.current;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 160),
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
