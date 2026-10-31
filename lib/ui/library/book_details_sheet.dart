import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import '../notes/book_notes_screen.dart';
import '../reader/open_book.dart';
import '../theme.dart';
import 'book_cover.dart';

Future<void> showBookDetails(BuildContext context, Book book) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _BookDetailsSheet(bookId: book.id),
  );
}

class _BookDetailsSheet extends StatelessWidget {
  const _BookDetailsSheet({required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context);
    final book = library.bookById(bookId);
    if (book == null) return const SizedBox(height: 80);
    final notes = library.annotationCountFor(book.id);
    final navigator = Navigator.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 138,
                child: BookCover(book: book, showStatus: false),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: kSerifFont,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      style: const TextStyle(color: HearthColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        book.format.name.toUpperCase(),
                        '${(book.progress * 100).round()}% read',
                        '$notes ${notes == 1 ? 'note' : 'notes'}',
                      ].join('  ·  '),
                      style: const TextStyle(
                        color: HearthColors.textFaint,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        minHeight: 3,
                        backgroundColor: HearthColors.outline,
                        color: book.status == ReadingStatus.read
                            ? HearthColors.readGreen
                            : HearthColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SegmentedButton<ReadingStatus>(
            segments: [
              for (final s in ReadingStatus.values)
                ButtonSegment(
                  value: s,
                  label: Text(s.label),
                  icon: Icon(switch (s) {
                    ReadingStatus.tbr => Icons.bookmark_border,
                    ReadingStatus.reading => Icons.auto_stories_outlined,
                    ReadingStatus.read => Icons.check_circle_outline,
                  }),
                ),
            ],
            selected: {book.status},
            onSelectionChanged: (s) => library.setStatus(book, s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              navigator.pop();
              openBook(navigator.context, book);
            },
            icon: const Icon(Icons.menu_book),
            label: Text(
              book.progress > 0 && book.status != ReadingStatus.read
                  ? 'Continue reading'
                  : 'Read',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              navigator.pop();
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (context) => BookNotesScreen(
                    book: book,
                    onOpenAt: (a) {
                      Navigator.pop(context);
                      openBook(navigator.context, book, annotation: a);
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.sticky_note_2_outlined),
            label: Text('Notes & highlights ($notes)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _editDetails(context, book),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE08A80),
                  ),
                  onPressed: () => _confirmDelete(context, book),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editDetails(BuildContext context, Book book) async {
    final title = TextEditingController(text: book.title);
    final author = TextEditingController(text: book.author);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      await AppScope.read(context)
          .updateMetadata(book, title: title.text, author: author.text);
    }
    title.dispose();
    author.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
          '“${book.title}” and all of its highlights and notes will be '
          'deleted from this device. The original file you imported from '
          'is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB4554B),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final library = AppScope.read(context);
      Navigator.pop(context);
      await library.deleteBook(book);
    }
  }
}
