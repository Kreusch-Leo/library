import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'data/library_database.dart';
import 'data/models.dart';
import 'services/app_paths.dart';
import 'services/library_controller.dart';
import 'ui/app_scope.dart';
import 'ui/library/library_screen.dart';
import 'ui/theme.dart';

/// [args]: on desktop, PDF/EPUB paths passed on the command line (e.g. via
/// a file manager's "Open with") are imported into the library.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Literata',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // PDF covers are rendered via the engine API before any viewer widget.
  await pdfrxFlutterInitialize();

  final paths = await AppPaths.resolve();
  final db = await LibraryDatabase.open(paths.databasePath);
  final controller = LibraryController(db: db, paths: paths);
  await controller.load();

  runApp(HearthApp(controller: controller));

  final files = [
    for (final arg in args)
      if (BookFormat.fromPath(arg) != null && File(arg).existsSync()) File(arg),
  ];
  if (files.isNotEmpty) await controller.importFiles(files);
}

class HearthApp extends StatelessWidget {
  const HearthApp({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Hearth',
        debugShowCheckedModeBanner: false,
        theme: buildHearthTheme(),
        darkTheme: buildHearthTheme(),
        themeMode: ThemeMode.dark,
        // Some dependencies (markdown, HTML rendering) still use the legacy
        // `package:flutter/material.dart` theme; bridge ours to them.
        builder: (context, child) =>
            // Needed until those packages migrate to material_ui.
            // ignore: deprecated_member_use
            MaterialUiCompatibilityBridge(child: child!),
        home: const LibraryScreen(),
      ),
    );
  }
}
