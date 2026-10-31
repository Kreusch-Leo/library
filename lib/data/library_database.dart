import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'models.dart';

/// Local SQLite store for books, reading progress and annotations.
///
/// On Android this uses the platform `sqflite` plugin; on Linux (and other
/// desktops) it uses the FFI implementation backed by the system SQLite.
class LibraryDatabase {
  LibraryDatabase._(this._db);

  final Database _db;

  static const _schemaVersion = 3;

  static Future<LibraryDatabase> open(String path) async {
    final factory = _factory();
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
    return LibraryDatabase._(db);
  }

  /// Opens a throw-away in-memory database (used by tests).
  static Future<LibraryDatabase> openInMemory() async {
    ffi.sqfliteFfiInit();
    final db = await ffi.databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
    return LibraryDatabase._(db);
  }

  static DatabaseFactory _factory() {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return databaseFactory;
    }
    ffi.sqfliteFfiInit();
    return ffi.databaseFactoryFfi;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        format TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_hash TEXT NOT NULL UNIQUE,
        cover_path TEXT,
        status TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        last_opened_at INTEGER,
        progress REAL NOT NULL DEFAULT 0,
        position TEXT,
        current_page INTEGER NOT NULL DEFAULT 0,
        total_pages INTEGER NOT NULL DEFAULT 0,
        finished_at INTEGER
      )
    ''');
    await _createReadingLog(db);
    await db.execute('''
      CREATE TABLE annotations (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        selected_text TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        color INTEGER NOT NULL,
        locator TEXT NOT NULL,
        section_label TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX annotations_book ON annotations(book_id, created_at)',
    );
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE books ADD COLUMN current_page INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE books ADD COLUMN total_pages INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE books ADD COLUMN finished_at INTEGER');
      // Best guess for books finished before this was tracked.
      await db.execute(
        "UPDATE books SET finished_at = "
        "COALESCE(last_opened_at, added_at) WHERE status = 'read'",
      );
      await _createReadingLog(db);
    }
  }

  static Future<void> _createReadingLog(Database db) async {
    await db.execute('''
      CREATE TABLE reading_log (
        day TEXT NOT NULL,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        pages INTEGER NOT NULL,
        PRIMARY KEY (day, book_id)
      )
    ''');
  }

  Future<void> close() => _db.close();

  // ---- books -------------------------------------------------------------

  Future<List<Book>> allBooks() async {
    final rows = await _db.query('books', orderBy: 'added_at DESC');
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> bookById(String id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<Book?> bookByHash(String hash) async {
    final rows = await _db.query(
      'books',
      where: 'file_hash = ?',
      whereArgs: [hash],
    );
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<void> insertBook(Book book) => _db.insert('books', book.toRow());

  Future<void> updateBook(Book book) =>
      _db.update('books', book.toRow(), where: 'id = ?', whereArgs: [book.id]);

  Future<void> deleteBook(String id) =>
      _db.delete('books', where: 'id = ?', whereArgs: [id]);

  // ---- reading log ---------------------------------------------------------

  /// Adds [pages] to the tally for [bookId] on the day of [when].
  Future<void> logPages(
    String bookId,
    int pages,
    DateTime when,
  ) => _db.rawInsert(
    'INSERT INTO reading_log (day, book_id, pages) VALUES (?, ?, ?) '
    'ON CONFLICT(day, book_id) DO UPDATE SET pages = pages + excluded.pages',
    [ReadingLogEntry.dayKey(when), bookId, pages],
  );

  /// Log entries for days in [from, to) (local dates).
  Future<List<ReadingLogEntry>> readingLog(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'reading_log',
      where: 'day >= ? AND day < ?',
      whereArgs: [ReadingLogEntry.dayKey(from), ReadingLogEntry.dayKey(to)],
      orderBy: 'day ASC',
    );
    return rows.map(ReadingLogEntry.fromRow).toList();
  }

  // ---- annotations ---------------------------------------------------------

  Future<List<Annotation>> annotationsFor(String bookId) async {
    final rows = await _db.query(
      'annotations',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Annotation.fromRow).toList();
  }

  Future<Map<String, int>> annotationCounts() async {
    final rows = await _db.rawQuery(
      'SELECT book_id, COUNT(*) AS n FROM annotations GROUP BY book_id',
    );
    return {for (final r in rows) r['book_id']! as String: r['n']! as int};
  }

  Future<void> upsertAnnotation(Annotation a) => _db.insert(
    'annotations',
    a.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> deleteAnnotation(String id) =>
      _db.delete('annotations', where: 'id = ?', whereArgs: [id]);
}
