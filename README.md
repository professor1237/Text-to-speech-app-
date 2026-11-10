# T2S Reader

A text-to-speech EPUB reader for Android. Import a book, press play, and listen
while the app highlights each sentence and scrolls along with the voice.

## Features

**Reading**
- Imports EPUB 2 and EPUB 3 books
- Library with cover thumbnails (long-press a book to remove it)
- Chapter drawer, continuous vertical scrolling
- Remembers where you stopped in each book
- Books load in the background, so the app never freezes

**Listening**
- Uses the phone's default text-to-speech voice
- Play, pause, stop, previous sentence, next sentence
- Speed slider
- Double-tap any word to start speaking from that sentence
- Current sentence is highlighted, and the page follows along automatically
- Playback controls in the notification and on headphone buttons

**Term replacement**
- Change how words are spoken without changing the text on screen
- Supports plain text or regular expressions
- A broken rule is skipped instead of crashing the app

**Appearance**
- Light, dark or system theme
- Several accent colours
- Adjustable text size

## Download (Android)

1. Open this repository on GitHub and tap **Releases**.
2. Open **Developer Build**.
3. Download `app-release.apk` and install it.

The APK is built automatically by GitHub Actions every time code is pushed
to the `main` branch.

## Build it yourself

```bash
flutter pub get
flutter run
```

## Project layout

```
lib/
  main.dart                  App start, theme, notification setup
  models/
    block.dart               One paragraph, heading, list item or quote
    sentence.dart            Splits text into sentences
    term_rule.dart           Term replacement rules
  services/
    epub_service.dart        Reads EPUB files
    speech_controller.dart   Play, pause, skip, sentence queue
    audio_handler.dart       Notification and headphone buttons
    library_db.dart          Saved books list (SQLite)
    settings_service.dart    Theme, accent colour, text size
  screens/
    library_screen.dart      Book list and import
    reader_screen.dart       Reading page and player controls
    terms_screen.dart        Term replacement editor
    settings_sheet.dart      Appearance settings
  widgets/
    paragraph_view.dart      Double-tap and sentence highlight
```

## Notes

- Only Android builds are produced by the automatic build.
- Speech quality and available voices depend on your phone's text-to-speech engine.
- Sentence splitting is rule-based, so unusual abbreviations may split in the wrong place.
