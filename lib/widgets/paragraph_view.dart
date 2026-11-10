import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/block.dart';

class ParagraphView extends StatefulWidget {
  final Block block;
  final int? highlightStart;
  final int? highlightEnd;
  final ValueChanged<int> onDoubleTapChar;
  final TextStyle style;

  const ParagraphView({
    super.key,
    required this.block,
    required this.onDoubleTapChar,
    required this.style,
    this.highlightStart,
    this.highlightEnd,
  });

  @override
  State<ParagraphView> createState() => _ParagraphViewState();
}

class _ParagraphViewState extends State<ParagraphView> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (d) {
        final ro = _key.currentContext?.findRenderObject();
        if (ro is! RenderParagraph) return;
        final pos = ro.getPositionForOffset(ro.globalToLocal(d.globalPosition));
        widget.onDoubleTapChar(pos.offset);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: RichText(
          key: _key,
          text: TextSpan(style: widget.style, children: _spans()),
        ),
      ),
    );
  }

  List<TextSpan> _spans() {
    final t = widget.block.text;
    final s = widget.highlightStart;
    final e = widget.highlightEnd;
    if (s == null || e == null || s >= e || s >= t.length) {
      return [TextSpan(text: t)];
    }
    final end = e.clamp(0, t.length);
    return [
      if (s > 0) TextSpan(text: t.substring(0, s)),
      TextSpan(
        text: t.substring(s, end),
        style: const TextStyle(backgroundColor: Color(0x66FFC107)),
      ),
      if (end < t.length) TextSpan(text: t.substring(end)),
    ];
  }
}
