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

  Future<void> _addDialog() async {
    final find = TextEditingController();
    final replace = TextEditingController();
    bool regex = false;
    final result = await showDialog<TermRule>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New replacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: find,
                decoration: const InputDecoration(labelText: 'Find'),
              ),
              TextField(
                controller: replace,
                decoration: const InputDecoration(labelText: 'Replace with'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Regex'),
                value: regex,
                onChanged: (v) => setLocal(() => regex = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (find.text.isEmpty) return;
                Navigator.pop(
                  ctx,
                  TermRule(
                    find: find.text,
                    replace: replace.text,
                    regex: regex,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => _rules.add(result));
      _save();
    }
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
                final r = _rules[i];
                return ListTile(
                  title: Text('${r.find}  ->  ${r.replace}'),
                  subtitle: Text(r.regex ? 'regex' : 'plain text'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: r.enabled,
                        onChanged: (v) {
                          setState(() => _rules[i] = r.copyWith(enabled: v));
                          _save();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _rules.removeAt(i));
                          _save();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
