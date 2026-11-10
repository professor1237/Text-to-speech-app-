enum BlockType { paragraph, heading, listItem, quote }

class Block {
  final String text;
  final BlockType type;
  const Block(this.text, this.type);
}
