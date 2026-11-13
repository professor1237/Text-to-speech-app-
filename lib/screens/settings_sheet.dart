import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/sleep_timer.dart';
import '../services/speech_controller.dart';
import '../services/voice_service.dart';

/// Central place for app appearance and all reading/voice preferences.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final _speech = SpeechController.instance;
  double _rate = 0.5;
  double _pitch = 1.0;
  List<String> _engines = [];
  List<VoiceInfo> _voices = [];
  String? _engine;
  String? _voiceName;
  bool _loadingVoice = true;

  @override
  void initState() {
    super.initState();
    _loadVoiceSettings();
  }

  Future<void> _loadVoiceSettings() async {
    try {
      await _speech.initialize();
      final pitch = await VoiceService.savedPitch();
      final engine = await VoiceService.savedEngine();
      final voiceName = await VoiceService.savedVoiceName();
      final engines = await VoiceService.engines(_speech.tts);
      final voices = await VoiceService.voices(_speech.tts);
      if (!mounted) return;
      setState(() {
        _rate = _speech.rate;
        _pitch = pitch;
        _engine = engines.contains(engine) ? engine : null;
        _voiceName = voices.any((v) => v.name == voiceName) ? voiceName : null;
        _engines = engines;
        _voices = voices;
        _loadingVoice = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingVoice = false);
    }
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
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Widget _heading(String value) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _colorChoices(Map<String, Color> choices, Color current,
      Future<void> Function(Color) onSelected) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: choices.entries.map((entry) {
        final selected = current == entry.value;
        return Tooltip(
          message: entry.key,
          child: GestureDetector(
            onTap: () => onSelected(entry.value),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: entry.value,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: selected
                  ? Icon(Icons.check,
                      color: entry.value.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SettingsService.settingsPanelBackgroundColor,
      builder: (context, panelColor, _) => Material(
        color: panelColor,
        child: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text('Settings',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            _heading('App theme'),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: SettingsService.themeMode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    SettingsService.setThemeMode(s.first),
              ),
            ),
            _heading('App accent colour'),
            ValueListenableBuilder<Color>(
              valueListenable: SettingsService.seedColor,
              builder: (_, current, __) => _colorChoices(
                SettingsService.seedChoices,
                current,
                (color) {
                  final name = SettingsService.seedChoices.entries
                      .firstWhere((e) => e.value == color)
                      .key;
                  return SettingsService.setSeedColor(name);
                },
              ),
            ),
            _heading('Reader text size'),
            ValueListenableBuilder<double>(
              valueListenable: SettingsService.fontScale,
              builder: (_, scale, __) => Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.text_decrease),
                    onPressed: () => SettingsService.setFontScale(scale - 0.1),
                  ),
                  Expanded(
                    child: Slider(
                      value: scale,
                      min: 0.7,
                      max: 2.0,
                      divisions: 13,
                      label: '${(scale * 100).round()}%',
                      onChanged: SettingsService.setFontScale,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_increase),
                    onPressed: () => SettingsService.setFontScale(scale + 0.1),
                  ),
                ],
              ),
            ),
            _heading('Reader text colour'),
            ValueListenableBuilder<Color>(
              valueListenable: SettingsService.readerTextColor,
              builder: (_, color, __) => _colorChoices(
                SettingsService.readerTextChoices,
                color,
                SettingsService.setReaderTextColor,
              ),
            ),
            _heading('Settings panel background'),
            ValueListenableBuilder<Color>(
              valueListenable: SettingsService.settingsPanelBackgroundColor,
              builder: (_, color, __) => _colorChoices(
                SettingsService.settingsPanelBackgroundChoices,
                color,
                SettingsService.setSettingsPanelBackgroundColor,
              ),
            ),
            _heading('Reading speed'),
            Row(
              children: [
                const Icon(Icons.speed),
                Expanded(
                  child: Slider(
                    value: _rate.clamp(0.1, 2.0).toDouble(),
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
                    label: '${(_rate * 100).round()}%',
                    onChanged: (v) => setState(() => _rate = v),
                    onChangeEnd: _speech.setRate,
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text('${(_rate * 100).round()}%'),
                ),
              ],
            ),
            _heading('Voice pitch'),
            Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: _pitch.toStringAsFixed(1),
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: _speech.setPitch,
            ),
            _heading('Voice and speech engine'),
            if (_loadingVoice)
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
                    final voice = name == null
                        ? null
                        : _voices.firstWhere((v) => v.name == name);
                    _speech.changeVoice(voice);
                  },
                )
              else
                const Text('No voices reported by this speech engine.'),
            ],
            _heading('Sleep timer'),
            ValueListenableBuilder<Duration?>(
              valueListenable: SleepTimer.remaining,
              builder: (_, left, __) => Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final minutes in const [10, 15, 30, 45, 60])
                    ActionChip(
                      label: Text('$minutes min'),
                      onPressed: () => SleepTimer.start(minutes),
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
          ],
        ),
          ),
        ),
      ),
    );
  }
}
