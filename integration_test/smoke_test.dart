// End-to-end smoke test on a real device/desktop engine:
//
//   flutter test integration_test -d linux \
//     --dart-define=SAMPLES_DIR=/path/with/pdfs-and-epubs \
//     --dart-define=SHOTS_DIR=/where/to/save/screenshots
//
// Imports real files (PDF covers are rendered through PDFium), opens both
// readers, and saves a PNG of each screen for visual review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/library_database.dart';
import 'package:hearth_reader/data/models.dart';
import 'package:hearth_reader/main.dart';
import 'package:hearth_reader/services/app_paths.dart';
import 'package:hearth_reader/services/library_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

const samplesDir = String.fromEnvironment('SAMPLES_DIR');
const shotsDir = String.fromEnvironment('SHOTS_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shotKey = GlobalKey();

  Future<void> wait(WidgetTester tester, [int ms = 1500]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (shotsDir.isEmpty) return;
    final boundary = shotKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(shotsDir, '$name.png'))
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets('import, browse the shelf, read PDF and EPUB', (tester) async {
    expect(samplesDir, isNotEmpty, reason: 'pass --dart-define=SAMPLES_DIR');
    await pdfrxFlutterInitialize();

    final root = await Directory.systemTemp.createTemp('hearth_it');
    final paths = AppPaths(root);
    await paths.ensureExists();
    final db = await LibraryDatabase.open(paths.databasePath);
    final library = LibraryController(db: db, paths: paths);
    await library.load();

    final files = Directory(samplesDir)
        .listSync()
        .whereType<File>()
        .where((f) => BookFormat.fromPath(f.path) != null)
        .toList();
    final report = await library.importFiles(files);
    expect(report.failures, isEmpty, reason: '${report.failures}');
    expect(report.imported, hasLength(files.length));

    final pdf = library.books.firstWhere((b) => b.format == BookFormat.pdf);
    expect(pdf.coverPath, isNotNull, reason: 'PDF cover rendered by PDFium');
    expect(File(pdf.coverPath!).lengthSync(), greaterThan(1000));
    final epub = library.books.firstWhere((b) => b.title == 'The Lantern Keeper');

    // A mix of statuses so the shelf shows its badges.
    final others = library.books.where((b) => b != pdf && b != epub).toList();
    await library.setStatus(others[0], ReadingStatus.read);
    await library.setStatus(others[1], ReadingStatus.read);
    await library.savePosition(
        others[2], const ReadingPosition.epub(0, 0.5), 0.45);

    await library.addAnnotation(
      book: pdf,
      selectedText: 'The harbour lights came on one by one',
      locator: const AnnotationLocator.pdf(
          page: 1, rects: [PageRect(72, 693, 318, 676)]),
      sectionLabel: 'Page 1',
      note: 'Opening image: lights *against* fog.',
    );
    await library.addAnnotation(
      book: epub,
      selectedText: 'a hundred and twelve, the way her grandmother had taught her',
      locator: const AnnotationLocator.epub(chapter: 0, occurrence: 0),
      sectionLabel: 'One',
      note: '**112 steps** — family ritual.\n\n- recurring motif?',
      color: 0xFF8DB58A,
    );

    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: HearthApp(controller: library),
    ));
    await wait(tester, 2500);
    await shot(tester, '01_shelf');
    expect(find.text('All  ${files.length}'), findsOneWidget);

    // --- PDF reader ---------------------------------------------------------
    await tester.tap(find.bySemanticsLabel(RegExp('^${pdf.title}')));
    await wait(tester, 3500);
    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.text('Page 1 of 4'), findsOneWidget);
    await shot(tester, '02_pdf_reader');

    await tester.tap(find.byTooltip('Show original page colours'));
    await wait(tester, 1500);
    await shot(tester, '03_pdf_original_colours');
    await tester.tap(find.byTooltip('Dark pages'));
    await wait(tester, 300);

    await tester.tap(find.byType(BackButton));
    await wait(tester, 1200);

    // --- EPUB reader --------------------------------------------------------
    await tester.tap(find.bySemanticsLabel(RegExp('^The Lantern Keeper')));
    await wait(tester, 3000);
    await shot(tester, '04_epub_reader');
    expect(find.textContaining('a hundred and twelve', findRichText: true),
        findsWidgets);

    await tester.tap(find.byTooltip('Notes & highlights'));
    await wait(tester, 1500);
    expect(find.text('Go to passage'), findsOneWidget);
    await shot(tester, '05_epub_notes');

    // Jump back to the passage, then scroll a little and leave.
    await tester.tap(find.text('Go to passage'));
    await wait(tester, 2000);
    await tester.drag(find.byType(SingleChildScrollView).last,
        const Offset(0, -500));
    await wait(tester, 1500);
    await tester.tap(find.byType(BackButton));
    await wait(tester, 1500);

    final saved = library.bookById(epub.id)!;
    expect(saved.position?.chapter, 0);
    expect(saved.position!.offset!, greaterThan(0));
    expect(saved.status, ReadingStatus.reading);

    // --- details sheet ------------------------------------------------------
    await tester.longPress(find.bySemanticsLabel(RegExp('^The Lantern Keeper')));
    await wait(tester, 1200);
    await shot(tester, '06_details_sheet');
    expect(find.text('Notes & highlights (1)'), findsOneWidget);
    expect(find.text('Continue reading'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // --- phone-width layout -------------------------------------------------
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await wait(tester, 800);
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    await wait(tester, 1500);
    await shot(tester, '07_phone_shelf');
    expect(tester.takeException(), isNull);
    tester.view.reset();

    await db.close();
    await root.delete(recursive: true);
  });
}
