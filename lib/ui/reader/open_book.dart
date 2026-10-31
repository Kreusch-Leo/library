import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import 'epub_reader_screen.dart';
import 'pdf_reader_screen.dart';

/// Opens [book] in the right reader, optionally jumping to [annotation].
Future<void> openBook(
  BuildContext context,
  Book book, {
  Annotation? annotation,
}) async {
  final library = AppScope.read(context);
  if (!await File(book.filePath).exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The book file is missing from app storage.'),
      ),
    );
    return;
  }
  await library.markOpened(book);
  if (!context.mounted) return;
  final current = library.bookById(book.id) ?? book;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (current.format) {
        BookFormat.pdf => PdfReaderScreen(
          book: current,
          initialAnnotation: annotation,
        ),
        BookFormat.epub => EpubReaderScreen(
          book: current,
          initialAnnotation: annotation,
        ),
      },
    ),
  );
}
