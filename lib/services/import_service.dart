import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../data/library_database.dart';
import '../data/models.dart';
import 'app_paths.dart';
import 'epub_document.dart';

/// Outcome of importing a batch of files.
class ImportReport {
  final imported = <Book>[];
  final duplicates = <String>[];
  final failures = <String, String>{};

  bool get isEmpty =>
      imported.isEmpty && duplicates.isEmpty && failures.isEmpty;

  String summary() {
    final parts = <String>[
      if (imported.isNotEmpty)
        'Added ${imported.length} book${imported.length == 1 ? '' : 's'}',
      if (duplicates.isNotEmpty) '${duplicates.length} already on the shelf',
      if (failures.isNotEmpty) '${failures.length} could not be read',
    ];
    return parts.isEmpty ? 'Nothing imported' : parts.join(' · ');
  }
}

/// Copies books into app storage, extracts metadata and covers, and records
/// them in the database. Files are copied so the library keeps working even
/// if the original is moved, and because Android pickers hand out temporary
/// content URIs.
class ImportService {
  ImportService(this._db, this._paths);

  final LibraryDatabase _db;
  final AppPaths _paths;
  static const _uuid = Uuid();

  /// Imports a single book given a readable byte stream.
  ///
  /// Returns the new [Book], or `null` if an identical file was already
  /// imported (detected by SHA-256).
  Future<Book?> importStream({
    required String fileName,
    required Stream<List<int>> Function() open,
  }) async {
    final format = BookFormat.fromPath(fileName);
    if (format == null) {
      throw FormatException('Unsupported file type: $fileName');
    }

    final id = _uuid.v4();
    final dest = File(p.join(_paths.booksDir.path, '$id.${format.name}'));

    // Copy and hash in a single pass.
    final digestSink = _DigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    final out = dest.openWrite();
    try {
      await for (final chunk in open()) {
        hashInput.add(chunk);
        out.add(chunk);
      }
    } finally {
      await out.close();
      hashInput.close();
    }
    final hash = digestSink.value.toString();

    if (await _db.bookByHash(hash) != null) {
      await dest.delete();
      return null;
    }

    try {
      final meta = format == BookFormat.epub
          ? await _epubMetadata(dest.path, id)
          : await _pdfMetadata(dest.path, id, fileName);
      final book = Book(
        id: id,
        title: meta.title,
        author: meta.author,
        format: format,
        filePath: dest.path,
        fileHash: hash,
        coverPath: meta.coverPath,
        addedAt: DateTime.now(),
      );
      await _db.insertBook(book);
      return book;
    } catch (_) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
  }

  Future<Book?> importFile(File file) =>
      importStream(fileName: p.basename(file.path), open: file.openRead);

  /// Recursively finds PDF and EPUB files below [dir].
  static Future<List<File>> scanDirectory(Directory dir) async {
    final found = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && BookFormat.fromPath(entity.path) != null) {
        found.add(entity);
      }
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  /// Removes a book's files (the copy, cover and EPUB resource cache).
  Future<void> deleteFiles(Book book) async {
    Future<void> rm(FileSystemEntity e) async {
      if (await e.exists()) await e.delete(recursive: true);
    }

    await rm(File(book.filePath));
    if (book.coverPath != null) await rm(File(book.coverPath!));
    await rm(_paths.epubResourcesFor(book.id));
  }

  Future<_Meta> _epubMetadata(String path, String id) async {
    final epub = await EpubDocument.openFile(path);
    String? coverPath;
    final bytes = epub.coverBytes();
    if (bytes != null && epub.coverHref != null) {
      final ext = p.extension(epub.coverHref!).toLowerCase();
      final cover = File(
        p.join(_paths.coversDir.path, '$id${ext.isEmpty ? '.img' : ext}'),
      );
      await cover.writeAsBytes(bytes);
      coverPath = cover.path;
    }
    return _Meta(epub.title, epub.author, coverPath);
  }

  Future<_Meta> _pdfMetadata(String path, String id, String fileName) async {
    final doc = await PdfDocument.openFile(path);
    String? coverPath;
    try {
      if (doc.pages.isEmpty) throw const FormatException('PDF has no pages');
      final page = doc.pages.first;
      const targetWidth = 420.0;
      final scale = targetWidth / page.width;
      final w = targetWidth.round();
      final h = (page.height * scale).round();
      final image = await page.renderForDisplay(
        width: w,
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (image != null) {
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png != null) {
            final cover = File(p.join(_paths.coversDir.path, '$id.png'));
            await cover.writeAsBytes(png.buffer.asUint8List());
            coverPath = cover.path;
          }
        } finally {
          image.dispose();
        }
      }
    } finally {
      await doc.dispose();
    }
    return _Meta(titleFromFileName(fileName), 'Unknown author', coverPath);
  }

  /// "the_left_hand-of_darkness.pdf" -> "The left hand of darkness".
  static String titleFromFileName(String fileName) {
    final base = p
        .basenameWithoutExtension(fileName)
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (base.isEmpty) return 'Untitled';
    return base[0].toUpperCase() + base.substring(1);
  }
}

class _Meta {
  const _Meta(this.title, this.author, this.coverPath);
  final String title;
  final String author;
  final String? coverPath;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
