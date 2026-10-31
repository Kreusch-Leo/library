import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'annotation_editor.dart';

/// Consolidated list of every highlight and note in one book.
///
/// When [returnSelection] is true (opened from a reader) tapping "Go to
/// passage" pops with the chosen [Annotation]; otherwise [onOpenAt] is used.
class BookNotesScreen extends StatefulWidget {
  const BookNotesScreen({
    super.key,
    required this.book,
    this.returnSelection = false,
    this.onOpenAt,
  });

  final Book book;
  final bool returnSelection;
  final void Function(Annotation annotation)? onOpenAt;

  @override
  State<BookNotesScreen> createState() => _BookNotesScreenState();
}

enum _NotesFilter { all, withNotes }

class _BookNotesScreenState extends State<BookNotesScreen> {
  List<Annotation>? _annotations;
  _NotesFilter _filter = _NotesFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppScope.read(context).annotationsFor(widget.book.id);
    list.sort(_compareByPosition);
    if (mounted) setState(() => _annotations = list);
  }

  /// Order by position in the book, then by creation time.
  static int _compareByPosition(Annotation a, Annotation b) {
    int key(Annotation x) => x.locator.page ?? x.locator.chapter ?? 0;
    final byKey = key(a).compareTo(key(b));
    return byKey != 0 ? byKey : a.createdAt.compareTo(b.createdAt);
  }

  Future<void> _edit(Annotation a) async {
    final library = AppScope.read(context);
    final result = await showAnnotationEditor(
      context,
      quote: a.selectedText,
      initialNote: a.note,
      initialColor: a.color,
      canDelete: true,
      sectionLabel: a.sectionLabel,
    );
    switch (result) {
      case AnnotationSaved(:final note, :final color):
        await library.updateAnnotation(a.copyWith(note: note, color: color));
      case AnnotationDeleted():
        await library.deleteAnnotation(a);
      case null:
        return;
    }
    await _load();
  }

  void _goTo(Annotation a) {
    if (widget.returnSelection) {
      Navigator.pop(context, a);
    } else {
      widget.onOpenAt?.call(a);
    }
  }

  String _asMarkdown(List<Annotation> list) {
    final b = StringBuffer(
      '# ${widget.book.title}\n\n_${widget.book.author}_\n',
    );
    for (final a in list) {
      b.writeln();
      if (a.sectionLabel != null) b.writeln('### ${a.sectionLabel}\n');
      for (final line in a.selectedText.split('\n')) {
        b.writeln('> $line');
      }
      if (a.hasNote) b.writeln('\n${a.note}');
    }
    return b.toString();
  }

  Future<void> _export(List<Annotation> list) async {
    await Clipboard.setData(ClipboardData(text: _asMarkdown(list)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes copied to clipboard as Markdown')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _annotations;
    final shown = all == null
        ? null
        : _filter == _NotesFilter.all
        ? all
        : all.where((a) => a.hasNote).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notes & highlights'),
            Text(
              widget.book.title,
              style: const TextStyle(
                fontSize: 13,
                color: HearthColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (all != null && all.isNotEmpty)
            IconButton(
              tooltip: 'Copy all as Markdown',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _export(shown!),
            ),
        ],
      ),
      body: shown == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      SegmentedButton<_NotesFilter>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _NotesFilter.all,
                            label: Text('All (${all!.length})'),
                          ),
                          ButtonSegment(
                            value: _NotesFilter.withNotes,
                            label: Text(
                              'With notes (${all.where((a) => a.hasNote).length})',
                            ),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) =>
                            setState(() => _filter = s.first),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const _EmptyNotes()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) => Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: _AnnotationCard(
                                annotation: shown[i],
                                onEdit: () => _edit(shown[i]),
                                onGoTo:
                                    widget.returnSelection ||
                                        widget.onOpenAt != null
                                    ? () => _goTo(shown[i])
                                    : null,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({
    required this.annotation,
    required this.onEdit,
    this.onGoTo,
  });

  final Annotation annotation;
  final VoidCallback onEdit;
  final VoidCallback? onGoTo;

  @override
  Widget build(BuildContext context) {
    final a = annotation;
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(a.updatedAt);
    return Material(
      color: HearthColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QuoteBlock(text: a.selectedText, color: Color(a.color)),
              if (a.hasNote) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 6),
                  child: MarkdownBody(data: a.note),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        if (a.sectionLabel != null) a.sectionLabel!,
                        date,
                      ].join(' · '),
                      style: const TextStyle(
                        color: HearthColors.textFaint,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onGoTo != null)
                    TextButton.icon(
                      onPressed: onGoTo,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Go to passage'),
                    ),
                  IconButton(
                    tooltip: 'Edit note',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_note, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: 40,
              color: HearthColors.textFaint,
            ),
            SizedBox(height: 10),
            Text(
              'No highlights yet.\nSelect text while reading, then choose '
              '“Highlight” or “Add note”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HearthColors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
