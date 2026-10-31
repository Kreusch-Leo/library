import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/library_database.dart';
import '../data/models.dart';
import 'app_paths.dart';
import 'import_service.dart';

enum LibrarySort {
  recent('Recently opened'),
  added('Recently added'),
  title('Title'),
  author('Author');

  const LibrarySort(this.label);
  final String label;
}

/// App-wide state for the library: books, filters and annotations.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.db,
    required this.paths,
    ImportService? importer,
  }) : importer = importer ?? ImportService(db, paths);

  final LibraryDatabase db;
  final AppPaths paths;
  final ImportService importer;
  static const _uuid = Uuid();

  List<Book> _books = const [];
  Map<String, int> _annotationCounts = const {};
  ReadingStatus? _filter;
  LibrarySort _sort = LibrarySort.recent;
  String _query = '';
  bool _loading = true;
  bool _importing = false;

  bool get loading => _loading;
  bool get importing => _importing;
  ReadingStatus? get filter => _filter;
  LibrarySort get sort => _sort;
  String get query => _query;
  List<Book> get books => _books;

  int countFor(ReadingStatus? status) => status == null
      ? _books.length
      : _books.where((b) => b.status == status).length;

  int annotationCountFor(String bookId) => _annotationCounts[bookId] ?? 0;

  Book? bookById(String id) => _books.where((b) => b.id == id).firstOrNull;

  /// Books after applying the status filter, search query and sort order.
  List<Book> get visibleBooks {
    final q = _query.trim().toLowerCase();
    final list = _books.where((b) {
      if (_filter != null && b.status != _filter) return false;
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case LibrarySort.recent:
        list.sort(
          (a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(
            a.lastOpenedAt ?? a.addedAt,
          ),
        );
      case LibrarySort.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case LibrarySort.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case LibrarySort.author:
        list.sort(
          (a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
        );
    }
    return list;
  }

  Future<void> load() async {
    _books = await db.allBooks();
    _annotationCounts = await db.annotationCounts();
    _loading = false;
    notifyListeners();
  }

  void setFilter(ReadingStatus? status) {
    _filter = status;
    notifyListeners();
  }

  void setSort(LibrarySort sort) {
    _sort = sort;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  // ---- importing -----------------------------------------------------------

  /// Opens the system file picker and imports the chosen PDFs/EPUBs.
  Future<ImportReport?> pickAndImport() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Add books',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub'],
    );
    if (picked.isEmpty) return null;
    return _runImport([
      for (final f in picked) (name: f.name, open: () => f.xFile.openRead()),
    ]);
  }

  /// Desktop only: imports every PDF/EPUB found below a chosen folder.
  Future<ImportReport?> pickFolderAndImport() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Import folder');
    if (dir == null) return null;
    final files = await ImportService.scanDirectory(Directory(dir));
    return _runImport([
      for (final f in files) (name: f.path, open: f.openRead),
    ]);
  }

  Future<ImportReport> importFiles(List<File> files) =>
      _runImport([for (final f in files) (name: f.path, open: f.openRead)]);

  Future<ImportReport> _runImport(
    List<({String name, Stream<List<int>> Function() open})> sources,
  ) async {
    final report = ImportReport();
    _importing = true;
    notifyListeners();
    try {
      for (final src in sources) {
        try {
          final book = await importer.importStream(
            fileName: src.name,
            open: src.open,
          );
          if (book == null) {
            report.duplicates.add(src.name);
          } else {
            report.imported.add(book);
          }
        } catch (e) {
          report.failures[src.name] = e.toString();
        }
      }
    } finally {
      _importing = false;
      _books = await db.allBooks();
      notifyListeners();
    }
    return report;
  }

  // ---- book updates ----------------------------------------------------------

  Future<void> _replace(Book book) async {
    await db.updateBook(book);
    _books = [for (final b in _books) b.id == book.id ? book : b];
    notifyListeners();
  }

  Future<void> setStatus(Book book, ReadingStatus status) async {
    final current = bookById(book.id) ?? book;
    await _replace(
      current.copyWith(
        status: status,
        progress: status == ReadingStatus.read ? 1.0 : null,
      ),
    );
  }

  Future<void> updateMetadata(
    Book book, {
    required String title,
    required String author,
  }) async {
    final current = bookById(book.id) ?? book;
    await _replace(
      current.copyWith(
        title: title.trim().isEmpty ? current.title : title.trim(),
        author: author.trim().isEmpty ? current.author : author.trim(),
      ),
    );
  }

  Future<void> markOpened(Book book) async {
    final current = bookById(book.id) ?? book;
    await _replace(current.copyWith(lastOpenedAt: DateTime.now()));
  }

  /// Persists the reading position. Moves a TBR book to "Reading" once the
  /// reader has actually moved past the start.
  Future<void> savePosition(
    Book book,
    ReadingPosition position,
    double progress, {
    int? currentPage,
    int? totalPages,
  }) async {
    final current = bookById(book.id) ?? book;
    final clamped = progress.clamp(0.0, 1.0);
    final status = current.status == ReadingStatus.tbr && clamped > 0.005
        ? ReadingStatus.reading
        : current.status;
    await _replace(
      current.copyWith(
        position: position,
        progress: current.status == ReadingStatus.read ? 1.0 : clamped,
        status: status,
        currentPage: currentPage,
        totalPages: totalPages,
      ),
    );
  }

  Future<void> deleteBook(Book book) async {
    await db.deleteBook(book.id);
    await importer.deleteFiles(book);
    _books = _books.where((b) => b.id != book.id).toList();
    _annotationCounts = Map.of(_annotationCounts)..remove(book.id);
    notifyListeners();
  }

  // ---- annotations ------------------------------------------------------------

  Future<List<Annotation>> annotationsFor(String bookId) =>
      db.annotationsFor(bookId);

  Future<Annotation> addAnnotation({
    required Book book,
    required String selectedText,
    required AnnotationLocator locator,
    String? sectionLabel,
    String note = '',
    int color = Annotation.defaultColor,
  }) async {
    final now = DateTime.now();
    final annotation = Annotation(
      id: _uuid.v4(),
      bookId: book.id,
      selectedText: selectedText.trim(),
      locator: locator,
      sectionLabel: sectionLabel,
      note: note,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await db.upsertAnnotation(annotation);
    await _refreshCounts();
    return annotation;
  }

  Future<void> updateAnnotation(Annotation annotation) async {
    await db.upsertAnnotation(annotation);
    notifyListeners();
  }

  Future<void> deleteAnnotation(Annotation annotation) async {
    await db.deleteAnnotation(annotation.id);
    await _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    _annotationCounts = await db.annotationCounts();
    notifyListeners();
  }
}
