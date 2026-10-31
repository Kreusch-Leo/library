import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/library_database.dart';
import 'package:hearth_reader/data/models.dart';
import 'package:hearth_reader/main.dart';
import 'package:hearth_reader/services/app_paths.dart';
import 'package:hearth_reader/services/library_controller.dart';
import 'package:material_ui/material_ui.dart';

Book _book(
  String id,
  String title,
  ReadingStatus status, {
  double progress = 0,
}) => Book(
  id: id,
  title: title,
  author: 'Author $id',
  format: BookFormat.epub,
  filePath: '/nonexistent/$id.epub',
  fileHash: 'hash-$id',
  addedAt: DateTime(2026, 1, int.parse(id)),
  status: status,
  progress: progress,
);

void main() {
  late Directory tmp;
  late LibraryDatabase db;
  late LibraryController library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hearth_ui');
    db = await LibraryDatabase.openInMemory();
    for (final b in [
      _book('1', 'Wolf Hall', ReadingStatus.reading, progress: 0.4),
      _book('2', 'Piranesi', ReadingStatus.read, progress: 1),
      _book('3', 'Middlemarch', ReadingStatus.tbr),
    ]) {
      await db.insertBook(b);
    }
    library = LibraryController(db: db, paths: AppPaths(tmp));
    await library.load();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HearthApp(controller: library));
    // Fairy lights animate forever, so pump frames instead of settling.
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows the shelf with books and filter chips', (tester) async {
    await pumpApp(tester);

    expect(find.text('Hearth'), findsOneWidget);
    expect(find.text('All  3'), findsOneWidget);
    expect(find.text('TBR  1'), findsOneWidget);
    expect(find.text('Reading  1'), findsOneWidget);
    expect(find.text('Read  1'), findsOneWidget);

    // Generated covers render the titles.
    expect(find.text('Wolf Hall'), findsWidgets);
    expect(find.text('Piranesi'), findsWidgets);
    expect(find.text('Middlemarch'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('Wolf Hall.*40% read')),
      findsOneWidget,
    );
    // The finished book carries a green completion badge.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('books being read show a completion badge', (tester) async {
    await pumpApp(tester);
    // Wolf Hall is 40 % through; read and TBR books get no badge.
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.text('0%'), findsNothing);

    // Page counts, once a PDF reader has saved them, take precedence.
    final wolfHall = library.bookById('1')!;
    // Real database I/O has to run outside the test's fake clock.
    await tester.runAsync(
      () => library.savePosition(
        wolfHall,
        const ReadingPosition.pdf(45),
        0.44,
        currentPage: 45,
        totalPages: 100,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('45%'), findsOneWidget);
    expect(find.text('40%'), findsNothing);
  });

  testWidgets('filter chips narrow the shelf', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Read  1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Piranesi'), findsWidgets);
    expect(find.text('Wolf Hall'), findsNothing);
    expect(find.text('Middlemarch'), findsNothing);

    await tester.tap(find.text('TBR  1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Middlemarch'), findsWidgets);
    expect(find.text('Piranesi'), findsNothing);
  });

  testWidgets('long-press opens the details sheet', (tester) async {
    await pumpApp(tester);
    await tester.longPress(find.bySemanticsLabel(RegExp('^Middlemarch')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Read'), findsWidgets);
    expect(find.text('Notes & highlights (0)'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('lays out on a phone-sized screen', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('Wolf Hall'), findsWidgets);
  });
}
