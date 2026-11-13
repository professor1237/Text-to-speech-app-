# Tts

A text-to-speech reader for Android. Import a book or document, press play, and listen while the app highlights each sentence and scrolls along with the voice.

The name on the phone is **Tts**.

## Supported files

| Type | Notes |
|------|-------|
| EPUB | Chapters from the book's table of contents, cover image |
| PDF | Text PDFs only. Pages are grouped into chapters of 5 pages |
| TXT | Chapters found from "Chapter 1", "Part II" and similar lines |
| DOCX | Word documents. Headings become chapters |
| HTML / HTM | Web pages saved as files |
| MD | Markdown. Headings become chapters, code blocks are skipped |

Scanned PDFs (pictures of pages) and password-protected files cannot be read.

## Features

**Reading**
- Library with cover thumbnails (long-press a book to remove it)
- Chapter drawer, continuous vertical scrolling
- Remembers where you stopped in each book
- Files load in the background, so the app never freezes

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

## Extra screens

- **Browser** (globe icon): search or open any site, read the page aloud with sentence highlighting, auto-read, Android back button goes back a page, and "Save to library" keeps a page for later. Double-tap text on the page to start speaking from that sentence.
- **Type & Speak** (keyboard icon): type or paste text, or "Paste & speak".
- **Voice and sleep timer** (voice icon): pitch, speech engine, voice, and a timer that pauses reading after 10 to 60 minutes.
- **Search in book** (magnifier in the reader): lists every match, tap to jump.

## Download (Android)

1. Open this repository on GitHub and tap **Releases**.
2. Open **Developer Build**.
3. Download `app-release.apk` and install it.

The APK is built automatically by GitHub Actions every time code is pushed to the `main` branch.

## Build it yourself

```bash
git pull
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release --target-platform android-arm64
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
    book_parser.dart         Opens PDF, TXT, DOCX, HTML, Markdown
    epub_service.dart        Opens EPUB
    speech_controller.dart   Play, pause, skip, sentence queue
    audio_handler.dart       Notification and headphone buttons
    library_db.dart          Saved books list (SQLite)
    settings_service.dart    Theme, accent colour, text size
    web_reader_service.dart  Reads a web page into sentences
    voice_service.dart       Pitch, engine, and voice
    sleep_timer.dart         Pauses reading after a set time
  screens/
    library_screen.dart      Book list and import
    reader_screen.dart       Reading page and player controls
    browser_screen.dart      In-app browser reader
    type_speak_screen.dart   Type or paste text and speak it
    terms_screen.dart        Term replacement editor
    settings_sheet.dart      Appearance settings
    voice_sheet.dart         Voice and sleep timer
    search_dialog.dart       Search inside a book
  widgets/
    paragraph_view.dart      Double-tap and sentence highlight
```

## Notes

- Only Android builds are produced by the automatic build.
- Speech quality and available voices depend on your phone's text-to-speech engine.
- Sentence splitting is rule-based, so unusual abbreviations may split in the wrong place.
- PDF text is joined back into paragraphs by a simple rule, so columns, headers and footnotes may sound out of order in some PDFs.
- The internal package id stays `com.example.t2s_reader` so existing installs can update. The visible name is **Tts**.
