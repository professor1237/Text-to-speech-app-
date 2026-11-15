import 'block.dart';

enum ChapterDownloadStatus { pending, downloading, downloaded, failed }

class WebChapter {
  WebChapter({
    required this.title,
    required this.url,
    required this.order,
    this.selected = true,
    this.status = ChapterDownloadStatus.pending,
    this.blocks = const [],
    this.error,
  });

  final String title;
  final String url;
  int order;
  bool selected;
  ChapterDownloadStatus status;
  List<Block> blocks;
  String? error;
}