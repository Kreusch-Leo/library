import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/library_database.dart';
import 'package:hearth_reader/data/models.dart';
import 'package:hearth_reader/services/app_paths.dart';
import 'package:hearth_reader/services/import_service.dart';
import 'package:hearth_reader/services/library_controller.dart';
import 'package:path/path.dart' as p;

import 'support/fake_epub.dart';

void main() {
  late Directory tmp;
  late LibraryDatabase db;
  late LibraryController library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hearth_lib');
    final paths = AppPaths(tmp);
    await paths.ensureExists();
    db = await LibraryDatabase.openInMemory();
    library = LibraryController(db: db, paths: paths);
    await library.load();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<File> writeEpub(String name, {String title = 'The Lantern Keeper'}) =>
      File(p.join(tmp.path, name)).writeAsBytes(buildEpub(title: title));

  test(
    'imports an EPUB with metadata and cover, and skips duplicates',
    () async {
      final file = await writeEpub('lantern.epub');
      final report = await library.importFiles([file, file]);

      expect(report.imported, hasLength(1));
      expect(report.duplicates, hasLength(1));
      expect(report.summary(), 'Added 1 book · 1 already on the shelf');

      final book = library.books.single;
      expect(book.title, 'The Lantern Keeper');
      expect(book.author, 'Ada Moss');
      expect(book.format, BookFormat.epub);
      expect(book.status, ReadingStatus.tbr);
      expect(File(book.filePath).existsSync(), isTrue);
      expect(p.isWithin(tmp.path, book.filePath), isTrue);
      expect(File(book.coverPath!).readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('reports unreadable and unsupported files without aborting', () async {
    final bad = await File(p.join(tmp.path, 'broken.epub')).writeAsString('x');
    final txt = await File(p.join(tmp.path, 'notes.txt')).writeAsString('x');
    final good = await writeEpub('good.epub');
    final report = await library.importFiles([bad, txt, good]);
    expect(report.imported, hasLength(1));
    expect(report.failures.keys, containsAll([bad.path, txt.path]));
    // Failed copies are cleaned up.
    expect(Directory(p.join(tmp.path, 'books')).listSync(), hasLength(1));
  });

  test(
    'saving progress moves TBR to Reading and persists the position',
    () async {
      await library.importFiles([await writeEpub('a.epub')]);
      final book = library.books.single;

      await library.savePosition(
        book,
        const ReadingPosition.epub(1, 0.25),
        0.6,
      );
      final updated = library.bookById(book.id)!;
      expect(updated.status, ReadingStatus.reading);
      expect(updated.progress, 0.6);

      final reloaded = (await db.bookById(book.id))!;
      expect(reloaded.position?.chapter, 1);
      expect(reloaded.position?.offset, 0.25);
    },
  );

  test('saving a paginated position persists page counts', () async {
    await library.importFiles([await writeEpub('a.epub')]);
    final book = library.books.single;
    await library.savePosition(
      book,
      const ReadingPosition.pdf(12),
      0.11,
      currentPage: 12,
      totalPages: 100,
    );
    final reloaded = (await db.bookById(book.id))!;
    expect((reloaded.currentPage, reloaded.totalPages), (12, 100));
    expect(reloaded.completionPercent, 12);

    // Saving without page counts (EPUB) keeps whatever was stored.
    await library.savePosition(book, const ReadingPosition.epub(0, 0.5), 0.3);
    expect(library.bookById(book.id)!.totalPages, 100);
  });

  test('forward page turns are logged for stats; jumps are not', () async {
    await library.importFiles([await writeEpub('a.epub')]);
    var book = library.books.single;
    Future<void> at(int page) => library.savePosition(
      library.bookById(book.id)!,
      ReadingPosition.pdf(page),
      page / 200,
      currentPage: page,
      totalPages: 200,
    );
    await at(3); // first save of an unopened book counts from page 0
    await at(5);
    await at(4); // going back: not reading
    await at(80); // jump via contents: not reading
    await at(82);

    final today = DateTime.now();
    final log = await library.readingLog(
      DateTime(today.year, today.month, today.day),
      DateTime(today.year, today.month, today.day + 1),
    );
    expect(log.single.pages, 3 + 2 + 2);
  });

  test('finishing a book records when; un-finishing clears it', () async {
    await library.importFiles([await writeEpub('a.epub')]);
    final book = library.books.single;
    await library.setStatus(book, ReadingStatus.read);
    final finished = library.bookById(book.id)!.finishedAt;
    expect(finished, isNotNull);
    await library.setStatus(book, ReadingStatus.read);
    expect(library.bookById(book.id)!.finishedAt, finished);
    await library.setStatus(book, ReadingStatus.reading);
    expect((await db.bookById(book.id))!.finishedAt, isNull);
  });

  test('read books keep full progress', () async {
    await library.importFiles([await writeEpub('a.epub')]);
    final book = library.books.single;
    await library.setStatus(book, ReadingStatus.read);
    await library.savePosition(book, const ReadingPosition.epub(0, 0), 0.1);
    expect(library.bookById(book.id)!.progress, 1.0);
    expect(library.bookById(book.id)!.status, ReadingStatus.read);
  });

  test('filters, searches and sorts', () async {
    await library.importFiles([
      await writeEpub('b.epub', title: 'Birch'),
      await writeEpub('a.epub', title: 'Alder'),
      await writeEpub('c.epub', title: 'Cedar'),
    ]);
    final cedar = library.books.firstWhere((b) => b.title == 'Cedar');
    await library.setStatus(cedar, ReadingStatus.read);

    library.setSort(LibrarySort.title);
    expect(library.visibleBooks.map((b) => b.title), [
      'Alder',
      'Birch',
      'Cedar',
    ]);

    library.setFilter(ReadingStatus.read);
    expect(library.visibleBooks.map((b) => b.title), ['Cedar']);
    expect(library.countFor(ReadingStatus.tbr), 2);
    expect(library.countFor(null), 3);

    library.setFilter(null);
    library.setQuery('ald');
    expect(library.visibleBooks.map((b) => b.title), ['Alder']);
  });

  test('annotations round-trip and are removed with the book', () async {
    await library.importFiles([await writeEpub('a.epub')]);
    final book = library.books.single;

    final a = await library.addAnnotation(
      book: book,
      selectedText: '  lit at dusk ',
      locator: const AnnotationLocator.epub(chapter: 0, occurrence: 2),
      sectionLabel: 'Chapter 1',
    );
    await library.addAnnotation(
      book: book,
      selectedText: 'page text',
      locator: const AnnotationLocator.pdf(
        page: 3,
        rects: [PageRect(10, 700, 200, 688)],
      ),
      note: '**bold** idea',
    );
    expect(library.annotationCountFor(book.id), 2);

    await library.updateAnnotation(
      a.copyWith(note: 'A note', color: 0xFF8DB58A),
    );
    final stored = await library.annotationsFor(book.id);
    final epubNote = stored.firstWhere((x) => x.id == a.id);
    expect(epubNote.selectedText, 'lit at dusk');
    expect(epubNote.note, 'A note');
    expect(epubNote.color, 0xFF8DB58A);
    expect(epubNote.locator.chapter, 0);
    expect(epubNote.locator.occurrence, 2);
    final pdfNote = stored.firstWhere((x) => x.id != a.id);
    expect(pdfNote.locator.page, 3);
    expect(pdfNote.locator.rects.single.top, 700);
    expect(pdfNote.hasNote, isTrue);

    final resources = library.paths.epubResourcesFor(book.id)
      ..createSync(recursive: true);
    await library.deleteBook(book);
    expect(library.books, isEmpty);
    expect(await db.annotationsFor(book.id), isEmpty);
    expect(File(book.filePath).existsSync(), isFalse);
    expect(File(book.coverPath!).existsSync(), isFalse);
    expect(resources.existsSync(), isFalse);
  });

  test('titleFromFileName tidies file names', () {
    expect(
      ImportService.titleFromFileName('the_left-hand.of_darkness.pdf'),
      'The left hand of darkness',
    );
    expect(ImportService.titleFromFileName('___.pdf'), 'Untitled');
  });
}
