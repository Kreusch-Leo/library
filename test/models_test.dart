import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/models.dart';

Book _book({double progress = 0, int currentPage = 0, int totalPages = 0}) =>
    Book(
      id: 'b1',
      title: 'Title',
      author: 'Author',
      format: BookFormat.pdf,
      filePath: '/x.pdf',
      fileHash: 'h',
      addedAt: DateTime(2026),
      progress: progress,
      currentPage: currentPage,
      totalPages: totalPages,
    );

void main() {
  group('Book.completion', () {
    test('uses page counts when known', () {
      final book = _book(progress: 0.1, currentPage: 45, totalPages: 100);
      expect(book.completion, 0.45);
      expect(book.completionPercent, 45);
    });

    test('falls back to progress when there are no pages (EPUB)', () {
      expect(_book(progress: 0.666).completionPercent, 67);
    });

    test('is clamped to 0..100 %', () {
      expect(_book(currentPage: 12, totalPages: 10).completionPercent, 100);
      expect(_book(progress: -0.2).completionPercent, 0);
    });

    test('page counts survive a database row round-trip', () {
      final row = _book(currentPage: 7, totalPages: 20).toRow();
      expect(row['current_page'], 7);
      expect(row['total_pages'], 20);
      final back = Book.fromRow(row);
      expect((back.currentPage, back.totalPages), (7, 20));
    });

    test('rows without page columns read as unknown (0)', () {
      final row = _book().toRow()
        ..remove('current_page')
        ..remove('total_pages');
      final back = Book.fromRow(row);
      expect((back.currentPage, back.totalPages), (0, 0));
    });
  });
}
