import 'package:flutter/material.dart';
import '../services/sleep_timer.dart';
import '../services/speech_controller.dart';
import '../services/voice_service.dart';

/// Pitch, voice, speech engine and sleep timer.
class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key});

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final _speech = SpeechController.instance;
  double _pitch = 1.0;
  List<String> _engines = [];
  List<VoiceInfo> _voices = [];
  String? _engine;
  String? _voiceName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pitch = await VoiceService.savedPitch();
    final engine = await VoiceService.savedEngine();
    final voiceName = await VoiceService.savedVoiceName();
    final engines = await VoiceService.engines(_speech.tts);
    final voices = await VoiceService.voices(_speech.tts);
    if (!mounted) return;
    setState(() {
      _pitch = pitch;
      _engine = engines.contains(engine) ? engine : null;
      _voiceName = voices.any((v) => v.name == voiceName) ? voiceName : null;
      _engines = engines;
      _voices = voices;
      _loading = false;
    });
  }

  Future<void> _reloadVoices() async {
    final voices = await VoiceService.voices(_speech.tts);
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voiceName = null;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sleep timer', style: heading),
            const SizedBox(height: 8),
            ValueListenableBuilder<Duration?>(
              valueListenable: SleepTimer.remaining,
              builder: (_, left, __) => Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final m in const [10, 15, 30, 45, 60])
                    ActionChip(
                      label: Text('$m min'),
                      onPressed: () => SleepTimer.start(m),
                    ),
                  if (left != null) ...[
                    Text('Pausing in ${_fmt(left)}'),
                    TextButton(
                      onPressed: SleepTimer.cancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Pitch', style: heading),
            Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: _pitch.toStringAsFixed(1),
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: (v) => _speech.setPitch(v),
            ),
            const SizedBox(height: 16),
            const Text('Voice', style: heading),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              if (_engines.isNotEmpty)
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: _engine,
                  decoration: const InputDecoration(
                    labelText: 'Speech engine',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Phone default'),
                    ),
                    for (final e in _engines)
                      DropdownMenuItem<String?>(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) async {
                    setState(() => _engine = v);
                    await _speech.changeEngine(v);
                    await _reloadVoices();
                  },
                ),
              const SizedBox(height: 12),
              if (_voices.isNotEmpty)
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: _voiceName,
                  decoration: const InputDecoration(
                    labelText: 'Voice',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Engine default'),
                    ),
                    for (final v in _voices)
                      DropdownMenuItem<String?>(
                        value: v.name,
                        child: Text('${v.locale}  ${v.name}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (name) {
                    setState(() => _voiceName = name);
                    final v = name == null
                        ? null
                        : _voices.firstWhere((x) => x.name == name);
                    _speech.changeVoice(v);
                  },
                )
              else
                const Text('No voices reported by this speech engine.'),
            ],
          ],
        ),
      ),
    );
  }
}
