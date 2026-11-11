import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/book_parser.dart';
import '../services/library_db.dart';
import '../services/speech_controller.dart';
import 'reader_screen.dart';
import 'settings_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final books = await LibraryDB.all();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final src = file.path;
    if (src == null) return;

    final ext = extensionOf(file.name);
    if (!supportedBookExtensions.contains(ext)) {
      _snack('Unsupported file type ".$ext".\n'
          'Supported: ${supportedBookExtensions.join(', ')}');
      return;
    }

    setState(() => _importing = true);
    try {
      final bytes = await File(src).readAsBytes();
      // Heavy work runs in the background so the app never freezes.
      final book = await compute(
        BookParser.parse,
        BookInput(file.name, bytes, baseName(file.name)),
      );
      final title = (book.title.trim().isEmpty || book.title == 'Untitled')
          ? baseName(file.name)
          : book.title;
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'book_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(dest).writeAsBytes(bytes);
      await LibraryDB.insert(dest, title, book.author, book.cover);
      await _refresh();
    } catch (e) {
      _snack('Could not import this file: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Asks first, then removes the book, its saved copy and its reading position.
  Future<void> _confirmDelete(Map<String, dynamic> b) async {
    final title = (b['title'] as String?) ?? 'Untitled';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this book?'),
        content: Text('"$title" will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final path = b['path'] as String;
    final speech = SpeechController.instance;
    if (speech.owner == path) await speech.stop();

    await LibraryDB.delete(b['id'] as int);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete(); // free the storage space
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pos_$path');
    } catch (_) {}
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('T2S Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette),
            tooltip: 'Appearance',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SettingsSheet(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_importing) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No books yet.\nTap + to import a file.\n\n'
                            'EPUB, PDF, TXT, DOCX, HTML, MD',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _books.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final b = _books[i];
                          final cover = b['cover'] as Uint8List?;
                          return ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 60,
                              child: cover != null
                                  ? Image.memory(cover, fit: BoxFit.cover)
                                  : const Icon(Icons.menu_book),
                            ),
                            title: Text(b['title'] ?? 'Untitled'),
                            subtitle: Text(b['author'] ?? ''),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReaderScreen(
                                  filePath: b['path'] as String,
                                  title: b['title'] as String? ?? 'Untitled',
                                ),
                              ),
                            ),
                            onLongPress: () => _confirmDelete(b),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importing ? null : _import,
        tooltip: 'Import a file',
        child: const Icon(Icons.add),
      ),
    );
  }
}
