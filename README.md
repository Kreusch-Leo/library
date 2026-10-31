# Hearth

A purely local, dark-only e-reader for **PDF** and **EPUB**, built with Flutter
for **Android** and **Linux**. Books sit on a hand-painted espresso-wood
bookshelf lit by twinkling fairy lights. No accounts, no network, no cloud.

## Features

- **Library**: import PDFs/EPUBs (multi-select; whole folders on desktop;
  on Linux also `hearth_reader book.epub …` / "Open with").
  Files are copied into app storage and de-duplicated by SHA-256. Title,
  author and cover art come from EPUB metadata; PDF covers are rendered from
  page 1. Titles and authors can be edited.
- **Shelf filters**: All · TBR · Reading · Read, plus search and sorting.
  New books start as TBR and move to Reading automatically once you get past
  the first page.
- **Status on the shelf**: green check badge for finished books, a glowing
  progress strip and a completion badge (e.g. "45%") for books in progress,
  and a red ribbon for books with notes.
- **Progress tracking**: saved automatically (debounced) on page turn or
  scroll, and again when you leave the reader.
  - PDF: page number, plus `current_page` / `total_pages`, which drive the
    shelf's completion badge.
  - EPUB: spine (chapter) index plus scroll offset inside the chapter.
    Overall % is weighted by chapter size.
- **Kindle-style navigation**: tap the left 20 % of the page to go back, the
  right 20 % to go forward, and the centre to show or hide the menu. Taps on
  links and highlights still go to them, and drags / long presses are left
  for scrolling and text selection.
  - PDF: one page at a time, fitted to the screen; swiping and pinch-zoom are
    off. On desktop, the mouse wheel and arrow keys turn pages.
  - EPUB: edge taps move one screen, crossing into the next or previous
    chapter at the ends.
- **Highlights and Markdown notes**: select text, then choose *Highlight* or
  *Add note* (four colours). Tap a highlight to edit or delete it. Each book
  has a consolidated **Notes & highlights** view that jumps to the passage
  and can copy everything as Markdown.
- **Strict dark reader**: black background with warm off-white text.
  - EPUB: author colours, fonts and backgrounds are stripped. Text size and
    serif/sans are adjustable.
  - PDF: pages are "smart-inverted" (luminance inverted, hue preserved);
    toggle with the invert button if a document looks better in original
    colours. Highlights are drawn un-inverted on top.

## Tech choices

| Concern | Package | Why |
|---|---|---|
| PDF rendering | [`pdfrx`](https://pub.dev/packages/pdfrx) | PDFium-based, supports **Android and Linux**, with text selection and a page colour filter. `flutter_pdfview` is Android/iOS only, and Syncfusion's viewer needs a commercial or community licence. |
| EPUB | small in-house parser (`archive` + `xml`) + [`flutter_widget_from_html_core`](https://pub.dev/packages/flutter_widget_from_html_core) | Pure Dart, so it works on every platform. It also gives full control over the chapter HTML, which highlights need. `epub_view` doesn't expose that. |
| Storage | `sqflite` (Android) / `sqflite_common_ffi` (Linux) | Plain SQLite: `books` and `annotations` tables, with cascade delete. |
| Notes | `flutter_markdown_plus` | Markdown rendering. |
| Files | `file_picker`, `path_provider` | |
| UI | `material_ui` | Material now lives outside the Flutter framework. |
| Type | Literata (bundled, OFL) | A typeface designed for e-reading, so books look the same on Android and Linux. |

### How EPUB highlights are anchored

A highlight stores its chapter index, its exact text, and **which occurrence**
of that text in the chapter it is. When you select text, Flutter's
`SelectionListener` reports the selection's offset in the rendered text. The
app picks the matching occurrence nearest that offset. Matching ignores
whitespace, so a selection that crosses paragraphs maps correctly onto the
DOM. When a chapter renders, matched text nodes are wrapped in tappable
`<a href="hl:<id>">` spans (`lib/services/chapter_html.dart`).

## Layout

```
lib/
  data/        models + SQLite database
  services/    import, EPUB parser, chapter HTML/highlights, library state
  ui/library/  bookshelf, covers, decorations (wood, fairy lights, plants…)
  ui/reader/   PDF reader, EPUB reader, shared reader chrome
  ui/notes/    note editor + per-book notes list
test/          parser, highlight mapping, controller/DB, and widget tests
integration_test/  end-to-end smoke test with screenshots
```

## Building

Requires Flutter ≥ 3.47 (Dart 3.13).

**Linux** prerequisites (Debian/Ubuntu/Pop!_OS):

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter run -d linux            # or: flutter build linux --release
```

`clang` is also needed for `flutter test`: pdfrx compiles a small native
helper through Dart build hooks.

**Android**: install the Android SDK and NDK (Android Studio → SDK Manager),
then:

```sh
flutter run -d <device>         # or: flutter build apk --release
```

**Tests**:

```sh
flutter analyze
flutter test                     # unit + widget tests

# End-to-end on the real Linux engine: imports real files (PDF covers via
# PDFium), opens both readers, saves a screenshot of each screen.
flutter test integration_test -d linux \
  --dart-define=SAMPLES_DIR=/folder/with/books \
  --dart-define=SHOTS_DIR=/tmp/hearth-shots
```

On Ubuntu 24.04 / Pop!_OS, if the Linux build fails with
`cannot find -lstdc++`, also install `libstdc++-14-dev`.

App data lives in the platform's application-support directory (on Linux:
`~/.local/share/dev.kreusch.hearth_reader/`).
