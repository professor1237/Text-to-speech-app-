import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/epub_service.dart';
import '../services/library_db.dart';
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

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (res == null || res.files.isEmpty) return;
    final src = res.files.first.path;
    if (src == null) return;

    setState(() => _importing = true);
    try {
      final bytes = await File(src).readAsBytes();
      // Heavy work runs in the background so the app never freezes.
      final book = await compute(EpubService.parse, bytes);
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'book_${DateTime.now().millisecondsSinceEpoch}.epub');
      await File(dest).writeAsBytes(bytes);
      await LibraryDB.insert(dest, book.title, book.author, book.cover);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import this book: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
                        child: Text('No books yet. Tap + to import an EPUB.'))
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
                            onLongPress: () async {
                              await LibraryDB.delete(b['id'] as int);
                              await _refresh();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importing ? null : _import,
        tooltip: 'Import EPUB',
        child: const Icon(Icons.add),
      ),
    );
  }
}
