import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/models.dart';
import '../../services/library_controller.dart';
import '../app_scope.dart';
import '../notes/annotation_editor.dart';
import '../notes/book_notes_screen.dart';
import '../theme.dart';
import 'reader_chrome.dart';
import 'tap_zones.dart';

/// "Smart invert": invert luminance, then rotate hue 180° so colours keep
/// roughly their hue. White paper becomes black and black ink a warm
/// off-white (rows are scaled slightly to avoid pure, glaring white).
const _darkPageMatrix = <double>[
  0.5166, -1.2870, -0.1296, 0, 229.5, //
  -0.3728, -0.3763, -0.1260, 0, 223.1, //
  -0.3578, -1.2012, 0.7190, 0, 214.2, //
  0, 0, 0, 1, 0, //
];

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.book,
    this.initialAnnotation,
  });

  final Book book;
  final Annotation? initialAnnotation;

  /// Remembered for the session so every PDF opens the same way.
  static bool invertPages = true;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final _controller = PdfViewerController();
  late final LibraryController _library = AppScope.read(context);
  List<Annotation> _annotations = const [];
  List<PdfOutlineNode> _outline = const [];
  int _page = 1;
  int _pageCount = 0;

  /// Page a turn is animating towards, so quick repeated turns stack up
  /// instead of all aiming at the same neighbour.
  int? _pendingPage;
  double _wheelAccumulator = 0;
  Duration _lastWheelTurn = Duration.zero;
  bool _chromeVisible = true;
  bool _promptedFinish = false;
  Timer? _saveTimer;

  late final int _initialPage =
      widget.initialAnnotation?.locator.page ?? widget.book.position?.page ?? 1;

  @override
  void initState() {
    super.initState();
    _page = _initialPage;
    _loadAnnotations();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    super.dispose();
  }

  Future<void> _loadAnnotations() async {
    final list = await _library.annotationsFor(widget.book.id);
    if (!mounted) return;
    setState(() => _annotations = list);
    if (_controller.isReady) _controller.invalidate();
  }

  double get _progress => _pageCount <= 1
      ? (_pageCount == 1 ? 1 : 0)
      : (_page - 1) / (_pageCount - 1);

  void _savePosition() {
    if (_pageCount == 0) return;
    _library.savePosition(
      widget.book,
      ReadingPosition.pdf(_page),
      _progress.toDouble(),
      currentPage: _page,
      totalPages: _pageCount,
    );
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    if (page == _pendingPage) _pendingPage = null;
    setState(() => _page = page);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _savePosition);
    if (page == _pageCount && _pageCount > 1) _maybePromptFinish();
  }

  void _maybePromptFinish() {
    final book = _library.bookById(widget.book.id);
    if (_promptedFinish || book?.status == ReadingStatus.read) return;
    _promptedFinish = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Reached the last page.'),
        action: SnackBarAction(
          label: 'Mark as read',
          onPressed: () => _library.setStatus(widget.book, ReadingStatus.read),
        ),
      ),
    );
  }

  // ---- highlights ------------------------------------------------------------

  Future<void> _highlightSelection({required bool withNote}) async {
    final delegate = _controller.textSelectionDelegate;
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;

    final byPage = <int, List<PdfPageTextRange>>{};
    for (final r in ranges) {
      byPage.putIfAbsent(r.pageNumber, () => []).add(r);
    }
    final quote = ranges.map((r) => r.text).join(' ').trim();
    if (quote.isEmpty) return;

    var note = '';
    var color = Annotation.defaultColor;
    if (withNote) {
      if (!mounted) return;
      final result = await showAnnotationEditor(
        context,
        quote: quote,
        sectionLabel: 'Page ${ranges.first.pageNumber}',
      );
      if (result is! AnnotationSaved) return;
      note = result.note;
      color = result.color;
    }

    for (final MapEntry(key: page, value: pageRanges) in byPage.entries) {
      final rects = <PageRect>[
        for (final range in pageRanges)
          for (final frag in range.enumerateFragmentBoundingRects())
            PageRect(
              frag.bounds.left,
              frag.bounds.top,
              frag.bounds.right,
              frag.bounds.bottom,
            ),
      ];
      await _library.addAnnotation(
        book: widget.book,
        selectedText: pageRanges.map((r) => r.text).join(' '),
        locator: AnnotationLocator.pdf(page: page, rects: rects),
        sectionLabel: 'Page $page',
        note: note,
        color: color,
      );
    }
    await delegate.clearTextSelection();
    await _loadAnnotations();
  }

  Future<void> _editAnnotation(Annotation a) async {
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
    await _loadAnnotations();
  }

  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final a in _annotations) {
      if (a.locator.page != page.pageNumber || a.locator.rects.isEmpty) {
        continue;
      }
      final rects = [
        for (final r in a.locator.rects)
          PdfRect(
            r.left,
            r.top,
            r.right,
            r.bottom,
          ).toRectInDocument(page: page, pageRect: pageRect).inflate(1),
      ];
      final bounds = rects.reduce((x, y) => x.expandToInclude(y));
      // Paint opaque into a translucent layer so overlapping fragments
      // don't stack into darker patches.
      canvas.saveLayer(
        bounds.inflate(2),
        Paint()..color = const Color(0x66000000),
      );
      final paint = Paint()..color = Color(a.color);
      for (final r in rects) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)),
          paint,
        );
      }
      canvas.restore();
      if (a.hasNote) {
        final first = rects.first;
        canvas.drawCircle(
          Offset(first.left - 6, first.center.dy),
          3,
          Paint()..color = Color(a.color),
        );
      }
    }
  }

  Annotation? _annotationAt(Offset documentPosition) {
    if (!_controller.isReady) return null;
    final layouts = _controller.layout.pageLayouts;
    for (var i = 0; i < layouts.length; i++) {
      if (!layouts[i].contains(documentPosition)) continue;
      final page = _controller.pages[i];
      for (final a in _annotations.reversed) {
        if (a.locator.page != page.pageNumber) continue;
        for (final r in a.locator.rects) {
          final rect = PdfRect(
            r.left,
            r.top,
            r.right,
            r.bottom,
          ).toRectInDocument(page: page, pageRect: layouts[i]).inflate(2);
          if (rect.contains(documentPosition)) return a;
        }
      }
    }
    return null;
  }

  /// Kindle-style taps: a highlight under the finger always wins; otherwise
  /// the edges turn pages and the centre toggles the menu.
  void _onZoneTap(TapZone zone, Offset globalPosition) {
    if (!_controller.isReady) return;
    // With text selected, a tap only dismisses the selection (pdfrx does
    // that itself); turning the page as well would lose the user's place.
    if (_controller.textSelectionDelegate.hasSelectedText) return;
    final docPos = _controller.globalToDocument(globalPosition);
    final hit = docPos == null ? null : _annotationAt(docPos);
    if (hit != null) {
      _editAnnotation(hit);
      return;
    }
    switch (zone) {
      case TapZone.previous:
        _turnPage(-1);
      case TapZone.next:
        _turnPage(1);
      case TapZone.menu:
        setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  void _turnPage(int delta) {
    if (_pageCount == 0) return;
    final from = _pendingPage ?? _page;
    final target = (from + delta).clamp(1, _pageCount);
    if (target == from) return;
    _pendingPage = target;
    _goToPage(target);
  }

  /// Desktop: one wheel "notch" (or a trackpad swipe) turns one page.
  /// Free scrolling is off because it would stop between pages.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      final dy = scroll.scrollDelta.dy != 0
          ? scroll.scrollDelta.dy
          : scroll.scrollDelta.dx;
      const cooldown = Duration(milliseconds: 250);
      if (scroll.timeStamp - _lastWheelTurn < cooldown) return;
      _wheelAccumulator += dy;
      if (_wheelAccumulator.abs() < 40) return;
      _turnPage(_wheelAccumulator > 0 ? 1 : -1);
      _wheelAccumulator = 0;
      _lastWheelTurn = scroll.timeStamp;
    });
  }

  /// Arrow keys turn pages rather than panning into the gap between pages.
  /// Other keys (PageUp/Down, Space, Home/End, Ctrl+C) keep pdfrx defaults.
  bool? _onKey(
    PdfViewerKeyHandlerParams params,
    LogicalKeyboardKey key,
    bool _,
  ) {
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _turnPage(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _turnPage(-1);
      return true;
    }
    return null;
  }

  /// Shows [page] scaled so the whole page fits the viewport.
  Future<void> _goToPage(int page, {Duration? duration}) =>
      _controller.goToPage(
        pageNumber: page,
        anchor: PdfPageAnchor.all,
        duration: duration ?? const Duration(milliseconds: 160),
      );

  /// One page per "screen": pages are stacked vertically with a gap larger
  /// than any page, so a neighbour never peeks in when a page is fitted.
  static PdfPageLayout _singlePageLayout(
    List<PdfPage> pages,
    PdfViewerParams params,
  ) {
    final maxW = pages.fold<double>(0, (m, p) => p.width > m ? p.width : m);
    final maxH = pages.fold<double>(0, (m, p) => p.height > m ? p.height : m);
    final gap = 2 * (maxW > maxH ? maxW : maxH);
    final rects = <Rect>[];
    var y = params.margin;
    for (final p in pages) {
      rects.add(
        Rect.fromLTWH(
          params.margin + (maxW - p.width) / 2,
          y,
          p.width,
          p.height,
        ),
      );
      y += p.height + gap;
    }
    return PdfPageLayout(
      pageLayouts: rects,
      documentSize: Size(maxW + params.margin * 2, y - gap + params.margin),
    );
  }

  // ---- navigation ------------------------------------------------------------------

  Future<void> _openNotes() async {
    final target = await Navigator.of(context).push<Annotation>(
      MaterialPageRoute(
        builder: (_) =>
            BookNotesScreen(book: widget.book, returnSelection: true),
      ),
    );
    await _loadAnnotations();
    final page = target?.locator.page;
    if (page != null) await _goToPage(page);
  }

  void _openOutline() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => _outline.isEmpty
            ? const Center(
                child: Text(
                  'This PDF has no table of contents.',
                  style: TextStyle(color: HearthColors.textMuted),
                ),
              )
            : ListView(
                controller: scroll,
                children: [
                  for (final (node, depth) in _flatten(_outline, 0))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(
                        left: 20.0 + depth * 18,
                        right: 16,
                      ),
                      title: Text(node.title),
                      trailing: node.dest == null
                          ? null
                          : Text(
                              '${node.dest!.pageNumber}',
                              style: const TextStyle(
                                color: HearthColors.textFaint,
                              ),
                            ),
                      onTap: () {
                        Navigator.pop(context);
                        _controller.goToDest(node.dest);
                      },
                    ),
                ],
              ),
      ),
    );
  }

  static Iterable<(PdfOutlineNode, int)> _flatten(
    List<PdfOutlineNode> nodes,
    int depth,
  ) sync* {
    for (final n in nodes) {
      yield (n, depth);
      yield* _flatten(n.children, depth + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invert = PdfReaderScreen.invertPages;
    return ReaderChrome(
      title: widget.book.title,
      subtitle: _pageCount == 0 ? null : 'Page $_page of $_pageCount',
      visible: _chromeVisible,
      progress: _progress.toDouble(),
      actions: [
        IconButton(
          tooltip: invert ? 'Show original page colours' : 'Dark pages',
          icon: Icon(invert ? Icons.invert_colors : Icons.invert_colors_off),
          onPressed: () {
            setState(() => PdfReaderScreen.invertPages = !invert);
          },
        ),
        IconButton(
          tooltip: 'Contents',
          icon: const Icon(Icons.toc),
          onPressed: _openOutline,
        ),
        IconButton(
          tooltip: 'Notes & highlights',
          icon: const Icon(Icons.sticky_note_2_outlined),
          onPressed: _openNotes,
        ),
      ],
      bottom: _pageCount > 1
          ? PageScrubber(
              value: _page,
              max: _pageCount,
              label: (v) => 'Page $v',
              onChanged: (v) => _goToPage(v, duration: Duration.zero),
            )
          : null,
      child: TapZones(
        onTap: _onZoneTap,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: PdfViewer.file(
            widget.book.filePath,
            controller: _controller,
            initialPageNumber: _initialPage,
            params: PdfViewerParams(
              backgroundColor: HearthColors.readerBackground,
              margin: 10,
              // Fixed, Kindle-like paging: each page is fitted to the screen and
              // only the tap zones move between pages (no swiping or pinching).
              layoutPages: _singlePageLayout,
              panEnabled: false,
              scaleEnabled: false,
              pageAnchor: PdfPageAnchor.all,
              pageAnchorEnd: PdfPageAnchor.all,
              scrollByMouseWheel: null,
              onKey: _onKey,
              // Re-fit the current page when the window or orientation changes.
              onViewSizeChanged: (viewSize, oldViewSize, controller) {
                if (oldViewSize != null && _pageCount > 0) {
                  _goToPage(_page, duration: Duration.zero);
                }
              },
              pageImageColorFilter: invert
                  ? const ColorFilter.matrix(_darkPageMatrix)
                  : null,
              pageDropShadow: const BoxShadow(
                color: Color(0x33FFFFFF),
                blurRadius: 0,
                spreadRadius: 0.5,
              ),
              onViewerReady: (document, controller) async {
                setState(() {
                  _pageCount = document.pages.length;
                  _page = _initialPage.clamp(1, _pageCount);
                });
                await _goToPage(_page, duration: Duration.zero);
                final outline = await document.loadOutline();
                if (mounted) setState(() => _outline = outline);
              },
              onPageChanged: _onPageChanged,
              pagePaintCallbacks: [_paintHighlights],
              textSelectionParams: const PdfTextSelectionParams(enabled: true),
              customizeContextMenuItems: (params, items) {
                if (!params.textSelectionDelegate.hasSelectedText) return;
                items.insertAll(0, [
                  ContextMenuButtonItem(
                    label: 'Highlight',
                    onPressed: () {
                      params.dismissContextMenu();
                      _highlightSelection(withNote: false);
                    },
                  ),
                  ContextMenuButtonItem(
                    label: 'Add note',
                    onPressed: () {
                      params.dismissContextMenu();
                      _highlightSelection(withNote: true);
                    },
                  ),
                ]);
              },
              loadingBannerBuilder: (context, _, _) =>
                  const Center(child: CircularProgressIndicator()),
              errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not open this PDF.\n${'$error'.split('\n').first}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: HearthColors.textMuted),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
