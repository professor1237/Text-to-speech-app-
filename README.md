# Tts

**Tts** is an Android text-to-speech reader for ebooks, documents, and web pages. Open a book, choose a sentence, and listen while the app highlights the text and follows along.

## Supported formats

| Format | Support |
|---|---|
| EPUB | Chapters from the book's table of contents and cover image |
| PDF | Text-based PDFs; pages are grouped into chapters of five |
| TXT | Chapter headings such as "Chapter 1" and "Part II" |
| DOCX | Word documents; headings become chapters |
| HTML / HTM | Web pages saved as files |
| Markdown (MD) | Headings become chapters; code blocks are skipped |

Scanned/image-only PDFs and password-protected files are not supported.

## Features

### Reading
- Import and manage books in a library with cover thumbnails.
- Read continuously with a chapter drawer and vertical scrolling.
- Remember the last reading position for each book.
- Load files in the background to keep the interface responsive.
- Search within a book and jump to a matching passage.

### Text-to-speech
- Use voices provided by the Android text-to-speech engine.
- Play, pause, stop, and move between sentences.
- Adjust speech speed and voice pitch.
- Double-tap a word or sentence to start reading from that point.
- Highlight the sentence currently being spoken and scroll along automatically.
- Control playback from the Android notification and supported headphone buttons.

### Term replacement
- Customize how words and phrases are pronounced without changing the displayed text.
- Use plain-text matching or regular expressions.
- Invalid regular-expression rules are skipped safely.

### Browser and typing
- Open web pages in the in-app browser and listen with sentence highlighting.
- Use browser navigation and save supported pages to the library.
- Paste or type text in **Type & Speak** and listen to it.

### Voice, appearance, and sleep timer
- Configure the available speech voice and engine, and adjust pitch.
- Choose light, dark, or system theme.
- Choose an accent colour and adjust reading text size.
- Set a sleep timer to pause reading after a selected interval.

## Download

1. Open the repository's [Releases](https://github.com/professor1237/Text-to-speech-app-/releases) page.
2. Open **Developer Build**.
3. Download `app-release.apk` and install it on your Android device.

The developer APK is built by GitHub Actions when changes are pushed to `main`. The workflow runs the Flutter tests before building the APK. A successful build also requires the Android signing secrets configured for this repository.

## Run locally

You need the Flutter SDK and Android development tools installed.

```bash
git clone https://github.com/professor1237/Text-to-speech-app-.git
cd Text-to-speech-app-
flutter pub get
flutter run
```

Run the automated tests:

```bash
flutter test
```

Build an Android release APK:

```bash
flutter build apk --release --target-platform android-arm64
```

## Project structure

```
lib/
  main.dart                  App entry point and theme setup
  models/
    block.dart               Paragraph, heading, list item, or quote
    sentence.dart            Sentence splitting
    term_rule.dart           Pronunciation replacement rules
  services/
    book_parser.dart         PDF, TXT, DOCX, HTML, and Markdown parsing
    epub_service.dart        EPUB parsing
    speech_controller.dart   Playback queue and speech controls
    audio_handler.dart       Notification and headphone controls
    library_db.dart          SQLite library storage
    settings_service.dart    Theme and reading settings
    web_reader_service.dart  Web-page text extraction
    voice_service.dart       Voice, pitch, and engine settings
    sleep_timer.dart         Timed playback pause
  screens/
    library_screen.dart      Library and file import
    reader_screen.dart       Book reading and playback
    browser_screen.dart      In-app browser reader
    type_speak_screen.dart   Typed or pasted text reader
    terms_screen.dart        Pronunciation rule editor
    settings_sheet.dart      Appearance settings
    voice_sheet.dart         Voice and sleep timer settings
    search_dialog.dart       Search within a book
  widgets/
    paragraph_view.dart      Sentence highlighting and text interaction
test/
  widget_test.dart            Parser and text-processing tests
```

## Known limitations

- The automatic release workflow currently produces Android APKs only.
- Speech quality and available voices depend on the text-to-speech engines installed on the device.
- Sentence splitting uses rules; unusual abbreviations or punctuation may be handled imperfectly.
- PDF text is reconstructed into paragraphs using heuristics. Multi-column layouts, headers, footnotes, and complex page designs may be read out of order.
- The Android application/package identifier is currently `com.example.t2s_reader`; the app's displayed name is **Tts**.
