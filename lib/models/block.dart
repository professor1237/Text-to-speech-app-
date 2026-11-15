enum BlockType { paragraph, heading, listItem, quote }

class Block {
  final String text;
  final BlockType type;

  /// Sanitized inline XHTML retained by WebToEpub. Null for legacy/plain blocks.
  final String? markup;

  const Block(this.text, this.type, {this.markup});
}
