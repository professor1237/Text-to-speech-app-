# T2S Reader

A text-to-speech EPUB reader for Android and iOS.

## Features
- Imports EPUB 2 / EPUB 3 books
- Uses the device's default system TTS voice
- Double-tap any word to start speaking from that sentence
- Continuous vertical scrolling with auto-follow while reading
- Term replacement rules applied to spoken text (visible text unchanged)
- Chapter drawer, cover thumbnails

## Run

```bash
flutter pub get
flutter run
```

## Layout

```
lib/
  main.dart
  models/        Block, Sentence, TermRule
  services/      EPUB parser, TTS controller, library DB
  screens/       Library, Reader, Term replacement
  widgets/       ParagraphView (double-tap -> char index -> highlight)
```
