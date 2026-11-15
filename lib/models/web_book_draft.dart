import 'web_chapter.dart';

class WebBookDraft {
  WebBookDraft({
    required this.sourceUrl,
    required this.title,
    required this.author,
    required this.chapters,
    this.coverUrl,
  });

  final String sourceUrl;
  String title;
  String author;
  String? coverUrl;
  final List<WebChapter> chapters;

  List<WebChapter> get selectedChapters =>
      chapters.where((chapter) => chapter.selected).toList();
}