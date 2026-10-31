import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/library_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('upgrading a v1 database adds page columns and keeps books', () async {
    final tmp = await Directory.systemTemp.createTemp('hearth_migrate');
    addTearDown(() => tmp.delete(recursive: true));
    final path = p.join(tmp.path, 'library.db');

    // Schema as shipped in version 1 (no current_page / total_pages).
    sqfliteFfiInit();
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL,
              format TEXT NOT NULL, file_path TEXT NOT NULL,
              file_hash TEXT NOT NULL UNIQUE, cover_path TEXT,
              status TEXT NOT NULL, added_at INTEGER NOT NULL,
              last_opened_at INTEGER, progress REAL NOT NULL DEFAULT 0,
              position TEXT
            )''');
          await db.insert('books', {
            'id': 'b1',
            'title': 'Old Book',
            'author': 'Someone',
            'format': 'pdf',
            'file_path': '/old.pdf',
            'file_hash': 'h1',
            'status': 'reading',
            'added_at': 0,
            'progress': 0.3,
          });
        },
      ),
    );
    await v1.close();

    final db = await LibraryDatabase.open(path);
    addTearDown(db.close);
    final book = (await db.bookById('b1'))!;
    expect(book.title, 'Old Book');
    expect((book.currentPage, book.totalPages), (0, 0));
    // No page data yet, so the badge falls back to the stored progress.
    expect(book.completionPercent, 30);

    await db.updateBook(book.copyWith(currentPage: 5, totalPages: 50));
    final updated = (await db.bookById('b1'))!;
    expect(updated.completionPercent, 10);
  });
}
