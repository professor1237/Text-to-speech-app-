import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart'; // global audioHandler
import '../models/sentence.dart';
import '../models/term_rule.dart';
import '../services/speech_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_sheet.dart';

/// Paste or type any text and have it read aloud.
class TypeSpeakScreen extends StatefulWidget {
  const TypeSpeakScreen({super.key});

  @override
  State<TypeSpeakScreen> createState() => _TypeSpeakScreenState();
}

class _TypeSpeakScreenState extends State<TypeSpeakScreen> {
  static const _owner = 'typed_text';
  static const _kDraft = 'typed_text_draft';

  final _speech = SpeechController.instance;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech.addListener(_onSpeech);
    _loadDraft();
  }

  @override
  void dispose() {
    _saveDraft();
    _speech.removeListener(_onSpeech);
    _controller.dispose();
    super.dispose();
  }

  void _onSpeech() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kDraft);
    if (t != null && mounted) _controller.text = t;
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDraft, _controller.text);
  }

  bool get _mine => _speech.owner == _owner;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.trim().isEmpty) return;
    setState(() => _controller.text = t);
  }

  Future<void> _pasteAndSpeak() async {
    await _paste();
    await _play();
  }

  Future<void> _play() async {
    if (_speech.state == SpeechState.paused && _mine) {
      _speech.resume();
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();

    final queue = <SentenceRef>[];
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    for (int i = 0; i < paragraphs.length; i++) {
      for (final s in splitSentences(paragraphs[i])) {
        queue.add(SentenceRef(0, i, s));
      }
    }
    if (queue.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final rules = decodeRules(prefs.getString('term_rules'));
    audioHandler.updateMediaItem(const MediaItem(
      id: _owner,
      title: 'Typed text',
      artist: 'T2S Reader',
    ));
    _speech.speak(queue, 0, rules, owner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    final playing = _speech.isPlaying && _mine;
    final active = _speech.isActive && _mine;
    final current = active ? _speech.current?.sentence.text.trim() : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Type & Speak'),
        actions: [
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            tooltip: 'Voice and sleep timer',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const VoiceSheet(),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _pasteAndSpeak,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Paste & speak'),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () {
                    _speech.stop();
                    setState(_controller.clear);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Type or paste text here',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (current != null && current.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(current, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 32,
                  onPressed: active ? () => _speech.skipPrev() : null,
                ),
                IconButton(
                  icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                  iconSize: 48,
                  onPressed: playing ? () => _speech.pause() : _play,
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle),
                  iconSize: 40,
                  onPressed: active ? () => _speech.stop() : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 32,
                  onPressed: active ? () => _speech.skipNext() : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
