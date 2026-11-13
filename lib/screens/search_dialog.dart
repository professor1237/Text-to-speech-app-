import 'package:flutter/material.dart';
import '../services/speech_controller.dart';

/// Search the whole book. Pops with the index of the chosen sentence.
class SearchDialog extends StatefulWidget {
  final List<SentenceRef> queue;
  final String Function(int chapter) chapterTitle;
  const SearchDialog({
    super.key,
    required this.queue,
    required this.chapterTitle,
  });

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  static const _maxResults = 200;
  final _controller = TextEditingController();
  List<int> _hits = [];
  String _query = '';
  late final List<String> _searchText = widget.queue
      .map((item) => item.sentence.text.toLowerCase())
      .toList(growable: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String q) {
    final needle = q.trim().toLowerCase();
    final hits = <int>[];
    if (needle.isNotEmpty) {
      for (int i = 0; i < _searchText.length; i++) {
        if (_searchText[i].contains(needle)) {
          hits.add(i);
          if (hits.length >= _maxResults) break;
        }
      }
    }
    setState(() {
      _query = needle;
      _hits = hits;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search in this book'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Type a word or phrase',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _hits.isEmpty
                  ? Center(
                      child: Text(_query.isEmpty
                          ? 'Type a word or character'
                          : 'No matches'),
                    )
                  : ListView.separated(
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, k) {
                        final ref = widget.queue[_hits[k]];
                        return ListTile(
                          dense: true,
                          title: Text(
                            ref.sentence.text.trim(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            widget.chapterTitle(ref.chapter),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, _hits[k]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
