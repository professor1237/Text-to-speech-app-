import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/web_book_draft.dart';
import '../models/web_chapter.dart';
import '../services/chapter_discovery_service.dart';
import '../services/chapter_fetch_service.dart';
import '../services/epub_service.dart';
import '../services/epub_writer_service.dart';
import '../services/library_db.dart';
import '../services/web_to_epub_service.dart';
import '../services/webview_fetch_service.dart';
import '../services/web_epub_settings_service.dart';

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
  late final ChapterDiscoveryService _discovery;
  late final ChapterFetchService _fetcher;
  late final WebViewFetchService _webView;
  late final WebToEpubService _singlePageService;
  WebBookDraft? _draft;
  bool _discovering = false;
  bool _downloading = false;
  bool _allowPartial = false;
  String? _error;
  String? _epubPath;
  int _completed = 0;
  int _total = 0;
  int _httpCount = 0;
  int _webViewCount = 0;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    final defaultTitle = widget.pageTitle.trim().isEmpty ? (uri?.host ?? 'Web novel') : widget.pageTitle.trim();
    _title = TextEditingController(text: defaultTitle);
    _author = TextEditingController(text: uri?.host ?? 'Unknown');
    _discovery = ChapterDiscoveryService();
    _fetcher = ChapterFetchService();
    _webView = WebViewFetchService();
    _singlePageService = WebToEpubService();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _discovery.close();
    _fetcher.close();
    _singlePageService.close();
    super.dispose();
  }

  Future<void> _discover() async {
    if (_discovering || _downloading) return;
    setState(() { _discovering = true; _error = null; _draft = null; _epubPath = null; });
    try {
      // Merge links from the raw HTTP response and the active, rendered
      // WebView. Some sites return a partial/non-empty HTTP page while their
      // actual chapter list is inserted by JavaScript.
      final discovered = <String, WebChapter>{};
      try {
        final httpChapters = await _discovery.discover(widget.url);
        for (final chapter in httpChapters) {
          discovered.putIfAbsent(chapter.url, () => chapter);
        }
      } catch (_) {
        // Continue with the rendered DOM; it may contain the client-side TOC.
      }
      try {
        final html = await widget.webViewFallback();
        final renderedChapters = _discovery.discoverFromHtml(html, widget.url);
        for (final chapter in renderedChapters) {
          discovered.putIfAbsent(chapter.url, () => chapter);
        }
      } catch (_) {
        // Preserve HTTP results if the WebView snapshot is unavailable.
      }
      final chapters = discovered.values.toList();
      if (chapters.isEmpty) {
        throw Exception('No chapter links were detected in the page. Open the novel table of contents and try again.');
      }
      if (!mounted) return;
      setState(() => _draft = WebBookDraft(
        sourceUrl: widget.url,
        title: _title.text.trim(),
        author: _author.text.trim(),
        chapters: chapters,
      ));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }


  /// Retains the original first-milestone behavior when a site has no
  /// discoverable table of contents or the user only wants the open page.
  Future<void> _createCurrentPage() async {
    if (_discovering || _downloading) return;
    setState(() { _discovering = true; _error = null; _epubPath = null; });
    String? output;
    try {
      final page = await _singlePageService.extractCurrentPage(
        url: widget.url,
        pageTitle: _title.text,
        webViewFallback: widget.webViewFallback,
      );
      final book = BookContent(
        _title.text.trim().isEmpty ? page.title : _title.text.trim(),
        _author.text.trim().isEmpty ? page.author : _author.text.trim(),
        null,
        [Chapter(page.title, page.blocks)],
      );
      final bytes = EpubWriterService.write(book);
      final parsed = await EpubService.parse(bytes);
      if (parsed.chapters.length != 1) throw Exception('Single-page EPUB validation failed.');
      final dir = await getApplicationDocumentsDirectory();
      output = p.join(dir.path, 'web_${DateTime.now().microsecondsSinceEpoch}_${_safeName(book.title)}.epub');
      await File(output).writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _epubPath = output);
    } catch (e) {
      if (output != null) {
        try { final file = File(output); if (await file.exists()) await file.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _error = 'Could not create EPUB from this page: $e');
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _openDownloadSettings() async {
    final host = Uri.parse(widget.url).host.toLowerCase();
    var profile = WebEpubSettingsService.forUri(Uri.parse(widget.url));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Download settings · $host', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<WebEpubDownloadMode>(
                  value: profile.mode,
                  decoration: const InputDecoration(labelText: 'Download method', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: WebEpubDownloadMode.adaptive, child: Text('Adaptive parallel')),
                    DropdownMenuItem(value: WebEpubDownloadMode.parallel, child: Text('Parallel')),
                    DropdownMenuItem(value: WebEpubDownloadMode.sequential, child: Text('One chapter at a time')),
                  ],
                  onChanged: (value) => setSheetState(() => profile = profile.copyWith(mode: value)),
                ),
                const SizedBox(height: 12),
                Text('Maximum parallel downloads: ${profile.maxParallel}'),
                Slider(value: profile.maxParallel.toDouble(), min: 1, max: 8, divisions: 7, onChanged: (v) => setSheetState(() => profile = profile.copyWith(maxParallel: v.round()))),
                Text('Delay between starting chapters: ${profile.delaySeconds} seconds'),
                Slider(value: profile.delaySeconds.toDouble(), min: 0, max: 10, divisions: 10, onChanged: (v) => setSheetState(() => profile = profile.copyWith(delaySeconds: v.round()))),
                Text('HTTP retries: ${profile.retries}'),
                Slider(value: profile.retries.toDouble(), min: 0, max: 5, divisions: 5, onChanged: (v) => setSheetState(() => profile = profile.copyWith(retries: v.round()))),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await WebEpubSettingsService.saveSite(host, profile);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Save settings for this website'),
                ),
                TextButton(
                  onPressed: () async {
                    await WebEpubSettingsService.saveSite(host, const WebEpubSiteProfile());
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Reset this website'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _download({bool retryOnly = false}) async {
    final draft = _draft;
    if (draft == null || _downloading) return;
    final targets = draft.chapters.where((c) =>
      c.selected && (retryOnly ? c.status == ChapterDownloadStatus.failed : c.status != ChapterDownloadStatus.downloaded)
    ).toList();
    if (targets.isEmpty) {
      setState(() => _error = 'Select at least one chapter that has not already downloaded.');
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
      _completed = 0;
      _total = targets.length;
      _httpCount = 0;
      _webViewCount = 0;
    });
    final profile = WebEpubSettingsService.forUri(Uri.parse(widget.url));
    final workers = profile.mode == WebEpubDownloadMode.sequential
        ? 1
        : profile.maxParallel.clamp(1, 10);
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (!mounted || nextIndex >= targets.length) return;
        final index = nextIndex++;
        final chapter = targets[index];
        if (profile.delaySeconds > 0 && index > 0) {
          await Future<void>.delayed(Duration(seconds: profile.delaySeconds));
        }
        if (!mounted) return;
        setState(() { chapter.status = ChapterDownloadStatus.downloading; chapter.error = null; });
        try {
          final result = await _fetcher.fetch(
            Uri.parse(chapter.url),
            webViewFallback: (uri) => _webView.fetch(uri),
            retries: profile.retries,
          );
          chapter.blocks = result.blocks;
          chapter.status = ChapterDownloadStatus.downloaded;
          if (result.method == 'HTTP') {
            _httpCount++;
          } else {
            _webViewCount++;
          }
        } catch (e) {
          chapter.status = ChapterDownloadStatus.failed;
          chapter.error = e.toString();
        }
        if (mounted) setState(() => _completed++);
      }
    }
    await Future.wait(List.generate(workers, (_) => worker()));
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _createEpub() async {
    final draft = _draft;
    if (draft == null) return;
    final successful = draft.chapters.where((c) => c.selected && c.status == ChapterDownloadStatus.downloaded).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final failed = draft.chapters.where((c) => c.selected && c.status == ChapterDownloadStatus.failed).length;
    if (successful.isEmpty) {
      setState(() => _error = 'No successfully downloaded chapters are available.');
      return;
    }
    if (failed > 0 && !_allowPartial) {
      setState(() => _error = '$failed selected chapter(s) failed. Retry them or enable creating an EPUB with successful chapters only.');
      return;
    }
    String? path;
    try {
      final book = BookContent(
        _title.text.trim().isEmpty ? 'Web novel' : _title.text.trim(),
        _author.text.trim().isEmpty ? 'Unknown' : _author.text.trim(),
        null,
        successful.map((c) => Chapter(c.title, c.blocks)).toList(),
      );
      final bytes = EpubWriterService.write(book);
      final parsed = await EpubService.parse(bytes);
      if (parsed.chapters.length != successful.length) {
        throw Exception('EPUB validation failed: expected ${successful.length} chapters, found ${parsed.chapters.length}.');
      }
      final dir = await getApplicationDocumentsDirectory();
      final safe = _safeName(book.title);
      path = p.join(dir.path, 'web_${DateTime.now().microsecondsSinceEpoch}_$safe.epub');
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() { _epubPath = path; _error = null; });
    } catch (e) {
      if (path != null) {
        try { final file = File(path); if (await file.exists()) await file.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _error = 'Could not create EPUB: $e');
    }
  }

  Future<void> _saveLibrary() async {
    final path = _epubPath;
    if (path == null) return;
    try {
      final book = await EpubService.parse(await File(path).readAsBytes());
      await LibraryDB.insert(path, book.title, book.author, book.cover);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EPUB saved to your library.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save to library: $e')));
    }
  }

  Future<void> _export() async {
    final path = _epubPath;
    if (path == null) return;
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export EPUB',
        fileName: '${_safeName(_title.text)}.epub',
        bytes: await File(path).readAsBytes(),
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EPUB export completed.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export EPUB: $e')));
    }
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();
    final safe = cleaned.isEmpty ? 'web_book' : cleaned;
    return safe.substring(0, safe.length > 70 ? 70 : safe.length);
  }

  void _reorder(int oldIndex, int newIndex) {
    final chapters = _draft?.chapters;
    if (chapters == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = chapters.removeAt(oldIndex);
      chapters.insert(newIndex, item);
      for (var i = 0; i < chapters.length; i++) { chapters[i].order = i; }
      _epubPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final selected = draft?.chapters.where((c) => c.selected).length ?? 0;
    final downloaded = draft?.chapters.where((c) => c.selected && c.status == ChapterDownloadStatus.downloaded).length ?? 0;
    final failed = draft?.chapters.where((c) => c.selected && c.status == ChapterDownloadStatus.failed).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('WebToEpub')),
      body: Stack(
        children: [
          // A WebViewController must be attached to a WebViewWidget before it
          // can reliably load pages. Keep the fallback view mounted at a tiny
          // size so chapter rendering works without replacing the browser tab.
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: WebViewWidget(controller: _webView.controller),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Book title', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _author, decoration: const InputDecoration(labelText: 'Author', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Text('Table of contents: ${widget.url}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _downloading ? null : _openDownloadSettings,
            icon: const Icon(Icons.tune),
            label: const Text('Download settings for this website'),
          ),
          FilledButton.icon(
            onPressed: _discovering || _downloading ? null : _discover,
            icon: const Icon(Icons.search),
            label: Text(draft == null ? 'Discover chapters' : 'Discover again'),
          ),
          OutlinedButton.icon(
            onPressed: _discovering || _downloading ? null : _createCurrentPage,
            icon: const Icon(Icons.article),
            label: const Text('Convert only this page'),
          ),
          if (_discovering) const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(),
          ),
          if (draft != null) ...[
            const SizedBox(height: 18),
            Text('${draft.chapters.length} chapters found · $selected selected', style: Theme.of(context).textTheme.titleMedium),
            Row(children: [
              TextButton(onPressed: _downloading ? null : () => setState(() {
                for (final c in draft.chapters) { c.selected = true; }
                _epubPath = null;
              }), child: const Text('Select all')),
              TextButton(onPressed: _downloading ? null : () => setState(() {
                for (final c in draft.chapters) { c.selected = false; }
                _epubPath = null;
              }), child: const Text('Deselect all')),
            ]),
            SizedBox(
              height: 360,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: true,
                itemCount: draft.chapters.length,
                onReorder: _reorder,
                itemBuilder: (context, index) {
                  final chapter = draft.chapters[index];
                  final statusIcon = switch (chapter.status) {
                    ChapterDownloadStatus.pending => Icons.radio_button_unchecked,
                    ChapterDownloadStatus.downloading => Icons.downloading,
                    ChapterDownloadStatus.downloaded => Icons.check_circle,
                    ChapterDownloadStatus.failed => Icons.error_outline,
                  };
                  return ListTile(
                    key: ValueKey(chapter.url),
                    dense: true,
                    leading: Checkbox(
                      value: chapter.selected,
                      onChanged: _downloading ? null : (v) => setState(() {
                        chapter.selected = v ?? false;
                        _epubPath = null;
                      }),
                    ),
                    title: Text(chapter.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: chapter.error == null ? null : Text(chapter.error!, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Icon(statusIcon, color: chapter.status == ChapterDownloadStatus.failed ? Theme.of(context).colorScheme.error : null),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _downloading || selected == 0 ? null : () => _download(),
              icon: const Icon(Icons.download),
              label: const Text('Download selected chapters'),
            ),
            if (_downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _total == 0 ? null : _completed / _total),
              Text('Processed $_completed of $_total chapters'),
            ],
            if (downloaded > 0) Text('$downloaded chapters downloaded · HTTP $_httpCount · WebView $_webViewCount'),
            if (failed > 0) ...[
              Text('$failed selected chapter(s) failed.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              OutlinedButton.icon(
                onPressed: _downloading ? null : () => _download(retryOnly: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry failed chapters'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowPartial,
                onChanged: (v) => setState(() => _allowPartial = v),
                title: const Text('Create EPUB with successful chapters only'),
              ),
            ],
            FilledButton.icon(
              onPressed: _downloading || downloaded == 0 ? null : _createEpub,
              icon: const Icon(Icons.menu_book),
              label: const Text('Create and validate EPUB'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_epubPath != null) Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('EPUB created and validated')]),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _saveLibrary, icon: const Icon(Icons.library_add), label: const Text('Save to library')),
                FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: const Text('Export EPUB')),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Some websites use JavaScript, login sessions, unusual navigation or access restrictions. Chapter discovery may need a site-specific adapter; inaccessible or incomplete chapters are reported rather than silently included.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}