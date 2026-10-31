import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/import_service.dart';
import '../../services/library_controller.dart';
import '../app_scope.dart';
import '../reader/open_book.dart';
import '../stats/stats_screen.dart';
import '../theme.dart';
import 'book_details_sheet.dart';
import 'bookshelf.dart';
import 'decor/fairy_lights.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "reduce motion" setting.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _twinkle
        ..stop()
        ..value = 0.25;
    } else if (!_twinkle.isAnimating) {
      _twinkle.repeat();
    }
  }

  @override
  void dispose() {
    _twinkle.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _import(Future<ImportReport?> Function() run) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await run();
      if (report == null || !mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(report.summary()),
          action: report.failures.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Details',
                  onPressed: () => _showFailures(report.failures),
                ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  void _showFailures(Map<String, String> failures) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Some files could not be imported'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in failures.entries) ...[
                Text(
                  e.key.split(Platform.pathSeparator).last,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  e.value,
                  style: const TextStyle(color: HearthColors.textMuted),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context);
    final books = library.visibleBooks;
    final isDesktop = !(Platform.isAndroid || Platform.isIOS);

    return Scaffold(
      body: DecoratedBox(
        // A warm pool of light high on the dark wall.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.3,
            colors: [Color(0xFF1E1610), HearthColors.background],
          ),
        ),
        child: Stack(
          children: [
            // Garland strung across the top of the room.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 60,
              child: LayoutBuilder(
                builder: (context, c) => FairyLights(
                  twinkle: _twinkle,
                  intensity: 0.8,
                  garlands: [
                    Garland.across(
                      left: -20,
                      right: c.maxWidth + 20,
                      y: 4,
                      segmentWidth: 300,
                      sag: 16,
                      bulbSpacing: 32,
                      seed: 1,
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _Header(
                    library: library,
                    searching: _searching,
                    searchController: _searchController,
                    isDesktop: isDesktop,
                    onToggleSearch: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) {
                        _searchController.clear();
                        library.setQuery('');
                      }
                    }),
                    onImportFiles: () => _import(library.pickAndImport),
                    onImportFolder: () => _import(library.pickFolderAndImport),
                  ),
                  _FilterChips(library: library),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: library.loading
                          ? const Center(child: CircularProgressIndicator())
                          : Bookshelf(
                              books: books,
                              twinkle: _twinkle,
                              noteCounts: {
                                for (final b in books)
                                  b.id: library.annotationCountFor(b.id),
                              },
                              emptyMessage: _emptyMessage(library),
                              onOpen: (book) => openBook(context, book),
                              onDetails: (book) =>
                                  showBookDetails(context, book),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (!library.loading && library.books.isEmpty)
              Center(
                child: _EmptyLibraryCard(
                  onImport: () => _import(library.pickAndImport),
                ),
              ),
            if (library.importing)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  String? _emptyMessage(LibraryController library) {
    if (library.books.isEmpty) return null;
    if (library.query.isNotEmpty) return 'No books match “${library.query}”';
    return switch (library.filter) {
      ReadingStatus.tbr => 'Nothing waiting on the TBR pile',
      ReadingStatus.reading => 'No book in progress right now',
      ReadingStatus.read => 'No finished books yet',
      null => null,
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.library,
    required this.searching,
    required this.searchController,
    required this.isDesktop,
    required this.onToggleSearch,
    required this.onImportFiles,
    required this.onImportFolder,
  });

  final LibraryController library;
  final bool searching;
  final TextEditingController searchController;
  final bool isDesktop;
  final VoidCallback onToggleSearch;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    final reading = library.countFor(ReadingStatus.reading);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: searching
                ? TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: library.setQuery,
                    decoration: const InputDecoration(
                      hintText: 'Search title or author',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hearth',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontFamily: kSerifFont,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  color: HearthColors.glow.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                      ),
                      Text(
                        '${library.books.length} books'
                        '${reading > 0 ? ' · $reading in progress' : ''}',
                        style: const TextStyle(
                          color: HearthColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            tooltip: searching ? 'Close search' : 'Search',
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: onToggleSearch,
          ),
          IconButton(
            tooltip: 'Reading stats',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
            ),
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: library.sort,
            onSelected: library.setSort,
            itemBuilder: (context) => [
              for (final s in LibrarySort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
          const SizedBox(width: 4),
          if (isDesktop)
            MenuAnchor(
              builder: (context, controller, _) => narrow
                  ? IconButton.filledTonal(
                      tooltip: 'Add books',
                      onPressed: controller.open,
                      icon: const Icon(Icons.add),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: controller.open,
                      icon: const Icon(Icons.add),
                      label: const Text('Add books'),
                    ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.description_outlined),
                  onPressed: onImportFiles,
                  child: const Text('Choose files…'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.folder_open_outlined),
                  onPressed: onImportFolder,
                  child: const Text('Import a folder…'),
                ),
              ],
            )
          else
            IconButton.filledTonal(
              tooltip: 'Add books',
              onPressed: onImportFiles,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.library});
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final options = <(ReadingStatus?, String)>[
      (null, 'All'),
      for (final s in ReadingStatus.values) (s, s.label),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (status, label) = options[i];
          final selected = library.filter == status;
          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => library.setFilter(status),
            avatar: status == ReadingStatus.read
                ? Icon(
                    Icons.check_circle,
                    size: 16,
                    color: selected
                        ? HearthColors.readGreen
                        : HearthColors.textFaint,
                  )
                : null,
            label: Text('$label  ${library.countFor(status)}'),
            labelStyle: TextStyle(
              color: selected ? HearthColors.text : HearthColors.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(
              color: selected
                  ? HearthColors.accent.withValues(alpha: 0.6)
                  : HearthColors.outline,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyLibraryCard extends StatelessWidget {
  const _EmptyLibraryCard({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: HearthColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HearthColors.outline),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 40,
            color: HearthColors.accent,
          ),
          const SizedBox(height: 12),
          Text(
            'Your shelves are waiting',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Add PDF or EPUB files from this device. Everything stays '
            'local: no accounts, no cloud.',
            textAlign: TextAlign.center,
            style: TextStyle(color: HearthColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('Add books'),
          ),
        ],
      ),
    );
  }
}
