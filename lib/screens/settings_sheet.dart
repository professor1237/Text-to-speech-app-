import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Theme',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: SettingsService.themeMode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode)),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => SettingsService.setThemeMode(s.first),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Accent colour',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ValueListenableBuilder<Color>(
              valueListenable: SettingsService.seedColor,
              builder: (_, current, __) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: SettingsService.seedChoices.entries.map((e) {
                  final selected = current == e.value;
                  return GestureDetector(
                    onTap: () => SettingsService.setSeedColor(e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Text size',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: SettingsService.fontScale,
              builder: (_, scale, __) => Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.text_decrease),
                    onPressed: () =>
                        SettingsService.setFontScale(scale - 0.1),
                  ),
                  Expanded(
                    child: Slider(
                      value: scale,
                      min: 0.7,
                      max: 2.0,
                      divisions: 13,
                      label: '${(scale * 100).round()}%',
                      onChanged: (v) => SettingsService.setFontScale(v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_increase),
                    onPressed: () =>
                        SettingsService.setFontScale(scale + 0.1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
