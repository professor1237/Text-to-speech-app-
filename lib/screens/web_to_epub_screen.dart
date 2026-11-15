import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/epub_service.dart';
import '../services/epub_writer_service.dart';
import '../services/library_db.dart';
import '../services/web_to_epub_service.dart';

class WebToEpubScreen extends StatefulWidget {
  const WebToEpubScreen({
    super.key, required this.url, required this.pageTitle, required this.webViewFallback,
  });
  final String url;
  final String pageTitle;
  final WebViewHtmlFallback webViewFallback;
  @override
  State<WebToEpubScreen> createState() => _WebToEpubScreenState();
}

class _WebToEpubScreenState extends State<WebToEpubScreen> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final WebToEpubService _service;
  bool _working = false;
  String? _path;
  String? _method;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    _title = TextEditingController(text: widget.pageTitle.trim().isEmpty ? (uri?.host ?? 'Web page') : widget.pageTitle.trim());
    _author = TextEditingController(text: uri?.host ?? 'Website');
    _service = WebToEpubService();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _create() async {
    if (_working) return;
    setState(() { _working = true; _error = null; _path = null; _method = null; });
    String? output;
    try {
      final page = await _service.extractCurrentPage(
        url: widget.url, pageTitle: _title.text, webViewFallback: widget.webViewFallback,
      );
      final book = BookContent(
        _title.text.trim().isEmpty ? page.title : _title.text.trim(),
        _author.text.trim().isEmpty ? page.author : _author.text.trim(),
        null,
        [Chapter(page.title, page.blocks)],
      );
      final bytes = EpubWriterService.write(book);
      final parsed = await EpubService.parse(bytes);
      if (parsed.chapters.isEmpty) throw Exception('Generated EPUB validation failed.');

      final dir = await getApplicationDocumentsDirectory();
      output = p.join(dir.path, 'web_\${DateTime.now().microsecondsSinceEpoch}_\${_safeName(book.title)}.epub');
      await File(output).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() { _path = output; _method = page.method; });
    } catch (e) {
      if (output != null) {
        try { final file = File(output); if (await file.exists()) await file.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveLibrary() async {
    final path = _path;
    if (path == null) return;
    try {
      final book = await EpubService.parse(await File(path).readAsBytes());
      await LibraryDB.insert(path, book.title, book.author, book.cover);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('EPUB saved to your library.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save to library: $e')),
      );
    }
  }

  Future<void> _export() async {
    final path = _path;
    if (path == null) return;
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Export EPUB',
        fileName: '\${_safeName(_title.text)}.epub',
        bytes: await File(path).readAsBytes(),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export EPUB: $e')),
      );
      return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('EPUB export completed.')),
    );
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();
    final safe = cleaned.isEmpty ? 'web_book' : cleaned;
    return safe.substring(0, safe.length > 70 ? 70 : safe.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download as EPUB')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Book title', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _author, decoration: const InputDecoration(labelText: 'Author / website', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Text(widget.url, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _working ? null : _create,
            icon: const Icon(Icons.download),
            label: const Text('Create EPUB from this page'),
          ),
          if (_working) ...[
            const SizedBox(height: 16), const LinearProgressIndicator(),
            const SizedBox(height: 8), const Text('Extracting page and validating EPUB…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            OutlinedButton.icon(onPressed: _working ? null : _create, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
          if (_path != null) ...[
            const SizedBox(height: 20),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('EPUB created and validated')]),
                if (_method != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Extraction method: $_method')),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _saveLibrary, icon: const Icon(Icons.library_add), label: const Text('Save to library')),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: const Text('Export EPUB')),
              ]),
            )),
          ],
          const SizedBox(height: 12),
          Text(
            'This first milestone converts the currently open page. Multi-chapter discovery and chapter selection are the next stage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}