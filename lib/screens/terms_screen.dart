import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/term_rule.dart';

class TermsScreen extends StatefulWidget {
  final List<TermRule> rules;
  const TermsScreen({super.key, required this.rules});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  late List<TermRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List.of(widget.rules);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('term_rules', encodeRules(_rules));
  }

  Future<void> _editDialog([int? editIndex]) async {
    final existing = editIndex == null ? null : _rules[editIndex];
    final find = TextEditingController(text: existing?.find ?? '');
    final replace = TextEditingController(text: existing?.replace ?? '');
    var regex = existing?.regex ?? false;
    var caseSensitive = existing?.caseSensitive ?? true;
    String? validationError;

    final result = await showDialog<TermRule>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New replacement' : 'Edit replacement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: find,
                  decoration: InputDecoration(
                    labelText: 'Find',
                    errorText: validationError,
                  ),
                  onChanged: (_) => setLocal(() => validationError = null),
                ),
                TextField(
                  controller: replace,
                  decoration: const InputDecoration(labelText: 'Replace with'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Regular expression'),
                  value: regex,
                  onChanged: (v) => setLocal(() {
                    regex = v ?? false;
                    validationError = null;
                  }),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Case-sensitive'),
                  value: caseSensitive,
                  onChanged: (v) =>
                      setLocal(() => caseSensitive = v ?? true),
                ),
                if (validationError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final pattern = find.text.trim();
                if (pattern.isEmpty) {
                  setLocal(() => validationError = 'Enter text to find.');
                  return;
                }
                if (regex) {
                  try {
                    RegExp(pattern, caseSensitive: caseSensitive);
                  } on FormatException {
                    setLocal(() => validationError = 'This regular expression is invalid.');
                    return;
                  }
                }
                Navigator.pop(
                  ctx,
                  TermRule(
                    find: pattern,
                    replace: replace.text,
                    regex: regex,
                    caseSensitive: caseSensitive,
                    enabled: existing?.enabled ?? true,
                  ),
                );
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    find.dispose();
    replace.dispose();
    if (result != null && mounted) {
      setState(() {
        if (editIndex == null) {
          _rules.add(result);
        } else {
          _rules[editIndex] = result;
        }
      });
      await _save();
    }
  }

  Future<void> _remove(int index) async {
    setState(() => _rules.removeAt(index));
    await _save();
  }

  Future<void> _toggleEnabled(int index, bool enabled) async {
    setState(() => _rules[index] = _rules[index].copyWith(enabled: enabled));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Term replacement')),
      body: _rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add pairs like "Dr." to "Doctor" or "&" to "and". '
                  'Only spoken text is replaced; the reading view stays unchanged.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final rule = _rules[i];
                return ListTile(
                  title: Text('${rule.find}  →  ${rule.replace}'),
                  subtitle: Text(
                    '${rule.regex ? 'regex' : 'plain text'} · '
                    '${rule.caseSensitive ? 'case-sensitive' : 'case-insensitive'}',
                  ),
                  onTap: () => _editDialog(i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: rule.enabled,
                        onChanged: (v) => _toggleEnabled(i, v),
                      ),
                      IconButton(
                        tooltip: 'Edit replacement',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editDialog(i),
                      ),
                      IconButton(
                        tooltip: 'Delete replacement',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(i),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _editDialog,
        tooltip: 'Add replacement',
        child: const Icon(Icons.add),
      ),
    );
  }
}
