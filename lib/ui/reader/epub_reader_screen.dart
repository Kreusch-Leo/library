import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../data/models.dart';
import '../../services/chapter_html.dart';
import '../../services/epub_document.dart';
import '../../services/library_controller.dart';
import '../app_scope.dart';
import '../notes/annotation_editor.dart';
import '../notes/book_notes_screen.dart';
import '../theme.dart';
import 'reader_chrome.dart';
import 'tap_zones.dart';

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({
    super.key,
    required this.book,
    this.initialAnnotation,
  });

  final Book book;
  final Annotation? initialAnnotation;

  /// Typography preferences, remembered for the session.
  static double fontSize = 19;
  static bool serif = true;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  late final LibraryController _library = AppScope.read(context);
  final _scroll = ScrollController();
  final _selection = SelectionListenerNotifier();
  final _chapterFraction = ValueNotifier<double>(0);
  final _focusNode = FocusNode(debugLabel: 'epub-reader');

  EpubDocument? _doc;
  Object? _error;
  String? _resourceRoot;
  List<int> _cumulative = const [0];
  List<Annotation> _annotations = const [];

  int _chapter = 0;
  ChapterHtml? _prepared;
  String _html = '';
  int _renderVersion = 0;
  String? _selectedText;
  bool _chromeVisible = true;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _scroll.dispose();
    _selection.dispose();
    _chapterFraction.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Parses the EPUB on a background isolate. Must be static: a closure
  /// created inside an instance method would capture `this` (and with it
  /// the widget tree), which cannot be sent to another isolate.
  static Future<EpubDocument> _parseOffMainThread(String path) =>
      Isolate.run(() => EpubDocument.openFile(path));

  Future<void> _open() async {
    try {
      final doc = await _parseOffMainThread(widget.book.filePath);
      final resources = _library.paths.epubResourcesFor(widget.book.id);
      await resources.create(recursive: true);
      await doc.extractResources(resources);
      final annotations = await _library.annotationsFor(widget.book.id);

      var total = 0;
      final cumulative = <int>[0];
      for (var i = 0; i < doc.chapters.length; i++) {
        total += doc.chapterSize(i);
        cumulative.add(total);
      }
      if (!mounted) return;
      _doc = doc;
      _resourceRoot = resources.path;
      _cumulative = cumulative;
      _annotations = annotations;

      final target = widget.initialAnnotation;
      if (target?.locator.chapter != null) {
        _showChapter(target!.locator.chapter!, focusOn: target);
      } else {
        final pos = widget.book.position;
        _showChapter(
          (pos?.chapter ?? 0).clamp(0, doc.chapters.length - 1),
          fraction: pos?.offset ?? 0,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  // ---- chapters & position ---------------------------------------------------------

  List<ChapterHighlight> _highlightsFor(int chapter) => [
    for (final a in _annotations)
      if (a.locator.chapter == chapter)
        ChapterHighlight(
          id: a.id,
          text: a.selectedText,
          occurrence: a.locator.occurrence,
          color: a.color,
        ),
  ];

  void _showChapter(int index, {double fraction = 0, Annotation? focusOn}) {
    final doc = _doc!;
    final prepared = ChapterHtml.prepare(
      doc.chapterHtml(index),
      chapterDir: p.posix.dirname(doc.chapters[index].href),
      resourceRoot: _resourceRoot,
    );
    if (focusOn != null) {
      fraction =
          prepared.fractionOf(
            focusOn.selectedText,
            focusOn.locator.occurrence,
          ) ??
          0;
    }
    setState(() {
      _chapter = index;
      _prepared = prepared;
      _html = prepared.render(_highlightsFor(index));
      _renderVersion++;
      _selectedText = null;
    });
    _chapterFraction.value = fraction;
    _restoreScroll(fraction, centerTarget: focusOn != null);
    _scheduleSave();
  }

  /// Jumps to [fraction] of the chapter once it has been laid out.
  void _restoreScroll(double fraction, {bool centerTarget = false}) {
    var attempts = 0;
    void attempt(Duration _) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      // Images may still be resolving; retry a few frames until the
      // extent settles.
      if (max == 0 && fraction > 0 && attempts++ < 10) {
        WidgetsBinding.instance.addPostFrameCallback(attempt);
        return;
      }
      final viewport = _scroll.position.viewportDimension;
      var target = fraction * (max + viewport);
      if (centerTarget) target -= viewport / 3;
      _scroll.jumpTo(target.clamp(0, max));
    }

    WidgetsBinding.instance.addPostFrameCallback(attempt);
  }

  double get _currentFraction {
    if (!_scroll.hasClients) return _chapterFraction.value;
    final pos = _scroll.position;
    final total = pos.maxScrollExtent + pos.viewportDimension;
    if (total <= 0) return 0;
    return (pos.pixels / total).clamp(0.0, 1.0);
  }

  double _overallProgress(double fraction) {
    final total = _cumulative.last;
    if (total == 0) return 0;
    final start = _cumulative[_chapter];
    final size = _cumulative[_chapter + 1] - start;
    final atEnd =
        _chapter == _cumulative.length - 2 &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 4;
    if (atEnd) return 1;
    return (start + size * fraction) / total;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
  }

  void _savePosition() {
    if (_doc == null) return;
    final fraction = _currentFraction;
    _library.savePosition(
      widget.book,
      ReadingPosition.epub(_chapter, fraction),
      _overallProgress(fraction),
    );
  }

  void _goToChapter(int index) {
    final doc = _doc;
    if (doc == null || index < 0 || index >= doc.chapters.length) return;
    _showChapter(index);
  }

  void _scrollBy(double viewports) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (pos.pixels + pos.viewportDimension * viewports).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Turns one screenful forward or back, crossing chapter boundaries the way
  /// a paginated reader would.
  void _turnPage(int direction) {
    final doc = _doc;
    if (doc == null || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (direction > 0) {
      if (pos.extentAfter < 4) {
        _goToChapter(_chapter + 1);
      } else {
        _scrollBy(0.9);
      }
    } else {
      if (pos.extentBefore < 4) {
        if (_chapter > 0) _showChapter(_chapter - 1, fraction: 1);
      } else {
        _scrollBy(-0.9);
      }
    }
  }

  void _onZoneTap(TapZone zone, Offset _) {
    // With text selected, a tap only dismisses the selection.
    if ((_selectedText ?? '').isNotEmpty) return;
    switch (zone) {
      case TapZone.previous:
        _turnPage(-1);
      case TapZone.next:
        _turnPage(1);
      case TapZone.menu:
        setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.space) {
      _turnPage(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _turnPage(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _scrollBy(0.12);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _scrollBy(-0.12);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _goToChapter(_chapter + 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _goToChapter(_chapter - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- highlights -----------------------------------------------------------------------

  Future<void> _reloadHighlights() async {
    final annotations = await _library.annotationsFor(widget.book.id);
    if (!mounted || _prepared == null) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() {
      _annotations = annotations;
      _html = _prepared!.render(_highlightsFor(_chapter));
      _renderVersion++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  Future<void> _highlightSelection({required bool withNote}) async {
    final text = _selectedText?.trim() ?? '';
    final prepared = _prepared;
    if (text.isEmpty || prepared == null) return;

    final range = _selection.registered ? _selection.selection.range : null;
    final start = range == null
        ? null
        : min(range.startOffset, range.endOffset);
    final occurrence = prepared.occurrenceNear(text, start);
    if (occurrence == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't anchor that selection; try selecting "
            'within the main text.',
          ),
        ),
      );
      return;
    }

    final label = _doc!.chapters[_chapter].title;
    var note = '';
    var color = Annotation.defaultColor;
    if (withNote) {
      final result = await showAnnotationEditor(
        context,
        quote: text,
        sectionLabel: label,
      );
      if (result is! AnnotationSaved) return;
      note = result.note;
      color = result.color;
    }
    await _library.addAnnotation(
      book: widget.book,
      selectedText: text,
      locator: AnnotationLocator.epub(
        chapter: _chapter,
        occurrence: occurrence,
      ),
      sectionLabel: label,
      note: note,
      color: color,
    );
    await _reloadHighlights();
  }

  Future<void> _editAnnotation(String id) async {
    final a = _annotations.where((a) => a.id == id).firstOrNull;
    if (a == null) return;
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
        await _library.updateAnnotation(a.copyWith(note: note, color: color));
      case AnnotationDeleted():
        await _library.deleteAnnotation(a);
      case null:
        return;
    }
    await _reloadHighlights();
  }

  Future<bool> _onTapUrl(String url) async {
    if (url.startsWith(highlightScheme)) {
      await _editAnnotation(url.substring(highlightScheme.length));
      return true;
    }
    if (url.startsWith(epubLinkScheme)) {
      final target = url.substring(epubLinkScheme.length).split('#').first;
      if (target.isEmpty) return true; // same-chapter anchor
      final index = _doc?.chapterIndexForHref(target) ?? -1;
      if (index >= 0) _goToChapter(index);
      return true;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Link copied: $url')));
    }
    return true;
  }

  Future<void> _openNotes() async {
    final target = await Navigator.of(context).push<Annotation>(
      MaterialPageRoute(
        builder: (_) =>
            BookNotesScreen(book: widget.book, returnSelection: true),
      ),
    );
    if (!mounted) return;
    final annotations = await _library.annotationsFor(widget.book.id);
    _annotations = annotations;
    final chapter = target?.locator.chapter;
    if (chapter != null) {
      _showChapter(chapter, focusOn: target);
    } else {
      await _reloadHighlights();
    }
  }

  void _openTypography() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(VoidCallback change) {
            setSheet(change);
            setState(() {});
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Text size',
                  style: TextStyle(color: HearthColors.textMuted),
                ),
                Row(
                  children: [
                    const Icon(Icons.text_decrease, size: 18),
                    Expanded(
                      child: Slider(
                        min: 14,
                        max: 30,
                        divisions: 16,
                        value: EpubReaderScreen.fontSize,
                        label: EpubReaderScreen.fontSize.round().toString(),
                        onChanged: (v) =>
                            update(() => EpubReaderScreen.fontSize = v),
                      ),
                    ),
                    const Icon(Icons.text_increase, size: 22),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Serif')),
                    ButtonSegment(value: false, label: Text('Sans')),
                  ],
                  selected: {EpubReaderScreen.serif},
                  onSelectionChanged: (s) =>
                      update(() => EpubReaderScreen.serif = s.first),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- rendering -------------------------------------------------------------------------------

  static String _rgba(int argb, double alpha) {
    final c = Color(argb);
    return 'rgba(${(c.r * 255).round()}, ${(c.g * 255).round()}, '
        '${(c.b * 255).round()}, $alpha)';
  }

  Map<String, String>? _styles(dom.Element element) {
    final tag = element.localName ?? '';
    final hl = element.attributes['data-hl'];
    if (hl != null) {
      final argb = int.tryParse(hl, radix: 16) ?? Annotation.defaultColor;
      return {
        'background-color': _rgba(argb, 0.32),
        'color': '#F4EFE6',
        'text-decoration': 'none',
      };
    }
    switch (tag) {
      case 'a':
        return {'color': '#E3AE62', 'text-decoration': 'none'};
      case 'h1' || 'h2' || 'h3':
        return {'line-height': '1.3', 'margin': '1.2em 0 0.6em 0'};
      case 'p':
        return {'margin': '0 0 0.9em 0'};
      case 'blockquote':
        return {'margin': '0.6em 0 0.6em 0.8em', 'font-style': 'italic'};
      case 'pre' || 'code':
        return {'background-color': '#14110F'};
      case 'hr':
        return {'border-top': '1px solid #3A342E'};
    }
    return null;
  }

  Widget _buildChapter() {
    final doc = _doc!;
    final isLast = _chapter == doc.chapters.length - 1;
    final textStyle = TextStyle(
      color: HearthColors.readerText,
      fontSize: EpubReaderScreen.fontSize,
      height: 1.6,
      fontFamily: EpubReaderScreen.serif ? kSerifFont : null,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0) {
          _chapterFraction.value = _currentFraction;
          if (n is ScrollEndNotification) _scheduleSave();
        }
        return false;
      },
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectionArea(
                    onSelectionChanged: (content) =>
                        _selectedText = content?.plainText,
                    contextMenuBuilder: (context, state) {
                      final hasText = (_selectedText ?? '').trim().isNotEmpty;
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: state.contextMenuAnchors,
                        buttonItems: [
                          if (hasText) ...[
                            ContextMenuButtonItem(
                              label: 'Highlight',
                              onPressed: () {
                                state.hideToolbar();
                                _highlightSelection(withNote: false);
                              },
                            ),
                            ContextMenuButtonItem(
                              label: 'Add note',
                              onPressed: () {
                                state.hideToolbar();
                                _highlightSelection(withNote: true);
                              },
                            ),
                          ],
                          ...state.contextMenuButtonItems,
                        ],
                      );
                    },
                    child: SelectionListener(
                      selectionNotifier: _selection,
                      child: HtmlWidget(
                        _html,
                        key: ValueKey('chapter-$_chapter-$_renderVersion'),
                        textStyle: textStyle,
                        buildAsync: false,
                        enableCaching: false,
                        customStylesBuilder: _styles,
                        onTapUrl: _onTapUrl,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  const Center(
                    child: Text(
                      '❦',
                      style: TextStyle(
                        color: HearthColors.textFaint,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!isLast)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: () => _goToChapter(_chapter + 1),
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(
                          'Next: ${doc.chapters[_chapter + 1].title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  else
                    Center(child: _FinishButton(book: widget.book)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToc() {
    final doc = _doc;
    return Drawer(
      backgroundColor: HearthColors.surface,
      child: SafeArea(
        child: doc == null
            ? const SizedBox()
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      doc.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (doc.toc.isEmpty)
                    for (var i = 0; i < doc.chapters.length; i++)
                      _tocTile(doc.chapters[i].title, i, 0)
                  else
                    for (final e in doc.toc)
                      _tocTile(e.title, e.chapterIndex, e.depth),
                ],
              ),
      ),
    );
  }

  Widget _tocTile(String title, int chapter, int depth) => Builder(
    builder: (context) => ListTile(
      dense: true,
      selected: chapter == _chapter,
      selectedColor: HearthColors.accent,
      contentPadding: EdgeInsets.only(left: 20.0 + depth * 16, right: 12),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.pop(context);
        _goToChapter(chapter);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not open this EPUB.\n${'$_error'.split('\n').first}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HearthColors.textMuted),
          ),
        ),
      );
    } else if (doc == null || _prepared == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: TapZones(onTap: _onZoneTap, child: _buildChapter()),
      );
    }

    return ValueListenableBuilder<double>(
      valueListenable: _chapterFraction,
      builder: (context, fraction, _) => ReaderChrome(
        title: widget.book.title,
        subtitle: doc == null ? null : doc.chapters[_chapter].title,
        visible: _chromeVisible,
        progress: doc == null ? null : _overallProgress(fraction),
        drawer: _buildToc(),
        actions: [
          IconButton(
            tooltip: 'Text settings',
            icon: const Icon(Icons.text_fields),
            onPressed: _openTypography,
          ),
          IconButton(
            tooltip: 'Notes & highlights',
            icon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: doc == null ? null : _openNotes,
          ),
        ],
        bottom: doc == null
            ? null
            : Row(
                children: [
                  IconButton(
                    tooltip: 'Previous chapter',
                    onPressed: _chapter > 0
                        ? () => _goToChapter(_chapter - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: doc.chapters.length > 1
                        ? PageScrubber(
                            value: _chapter + 1,
                            max: doc.chapters.length,
                            label: (v) => 'Section $v',
                            onChanged: (v) => _goToChapter(v - 1),
                          )
                        : const SizedBox(),
                  ),
                  Text(
                    '${(_overallProgress(fraction) * 100).round()}%',
                    style: const TextStyle(
                      color: HearthColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next chapter',
                    onPressed: _chapter < doc.chapters.length - 1
                        ? () => _goToChapter(_chapter + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
        child: body,
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context);
    final current = library.bookById(book.id) ?? book;
    if (current.status == ReadingStatus.read) {
      return const Text(
        'Finished ✓',
        style: TextStyle(color: HearthColors.readGreen),
      );
    }
    return FilledButton.icon(
      onPressed: () async {
        await library.setStatus(current, ReadingStatus.read);
        if (context.mounted) Navigator.pop(context);
      },
      icon: const Icon(Icons.check),
      label: const Text('Mark as read'),
    );
  }
}
