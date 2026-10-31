import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its private, purely local data.
class AppPaths {
  AppPaths(this.root);

  final Directory root;

  static Future<AppPaths> resolve() async {
    final base = await getApplicationSupportDirectory();
    final paths = AppPaths(base);
    await paths.ensureExists();
    return paths;
  }

  Directory get booksDir => Directory(p.join(root.path, 'books'));
  Directory get coversDir => Directory(p.join(root.path, 'covers'));
  Directory get epubCacheDir => Directory(p.join(root.path, 'epub_cache'));
  String get databasePath => p.join(root.path, 'library.db');

  Directory epubResourcesFor(String bookId) =>
      Directory(p.join(epubCacheDir.path, bookId));

  Future<void> ensureExists() async {
    for (final dir in [root, booksDir, coversDir, epubCacheDir]) {
      await dir.create(recursive: true);
    }
  }
}
