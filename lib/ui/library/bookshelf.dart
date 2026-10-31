import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'decor/fairy_lights.dart';
import 'decor/shelf_decor.dart';
import 'decor/wood.dart';

/// Something occupying one slot on a shelf.
sealed class ShelfItem {
  const ShelfItem();
}

class BookItem extends ShelfItem {
  const BookItem(this.book);
  final Book book;
}

class DecorItem extends ShelfItem {
  const DecorItem(this.kind, this.seed);
  final DecorKind kind;
  final int seed;
}

/// Pure geometry of the bookcase for a given width; shared by the painters
/// and the positioned children so everything lines up.
class ShelfLayout {
  ShelfLayout._({
    required this.width,
    required this.coverWidth,
    required this.coverHeight,
    required this.slotsPerRow,
    required this.gap,
    required this.contentLeft,
    required this.rows,
  });

  static const frame = 18.0; // side panel thickness
  static const crown = 30.0; // top board
  static const plank = 18.0; // shelf board thickness
  static const base = 26.0; // plinth below the last shelf
  static const headroom = 34.0; // space above covers in each cubby
  static const sidePadding = 14.0;

  final double width;
  final double coverWidth;
  final double coverHeight;
  final int slotsPerRow;
  final double gap;
  final double contentLeft;
  final int rows;

  factory ShelfLayout.compute(double width, int rows) {
    final coverWidth = width < 480
        ? 84.0
        : width < 900
        ? 100.0
        : 116.0;
    final coverHeight = coverWidth * 1.5;
    final gap = max(12.0, coverWidth * 0.16);
    final available = width - 2 * (frame + sidePadding);
    final slots = max(2, ((available + gap) / (coverWidth + gap)).floor());
    final used = slots * coverWidth + (slots - 1) * gap;
    final contentLeft = frame + sidePadding + (available - used) / 2;
    return ShelfLayout._(
      width: width,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
      slotsPerRow: slots,
      gap: gap,
      contentLeft: contentLeft,
      rows: 0,
    )._withRows(rows);
  }

  ShelfLayout _withRows(int rows) => ShelfLayout._(
    width: width,
    coverWidth: coverWidth,
    coverHeight: coverHeight,
    slotsPerRow: slotsPerRow,
    gap: gap,
    contentLeft: contentLeft,
    rows: rows,
  );

  double get rowHeight => headroom + coverHeight + plank;
  double get height => crown + rows * rowHeight + base;

  double rowTop(int row) => crown + row * rowHeight;
  double shelfSurface(int row) => rowTop(row) + headroom + coverHeight;
  double slotLeft(int slot) => contentLeft + slot * (coverWidth + gap);

  /// Decorations for a row: (slot index, kind). Fewer on narrow screens so
  /// books keep most of the room.
  List<(int, DecorKind)> decorFor(int row) {
    final last = slotsPerRow - 1;
    if (slotsPerRow <= 4) {
      return switch (row % 4) {
        0 => [(last, DecorKind.plant)],
        2 => [(0, DecorKind.bookStack)],
        _ => const [],
      };
    }
    return switch (row % 3) {
      0 => [(last, DecorKind.plant)],
      1 => [(0, DecorKind.bookStack)],
      _ => [(last, DecorKind.lightJar)],
    };
  }

  /// Distributes [books] over shelves (each row a list of nullable slots).
  List<List<ShelfItem?>> arrange(List<Book> books, {int minRows = 3}) {
    final rows = <List<ShelfItem?>>[];
    var i = 0;
    var r = 0;
    while (i < books.length || r < minRows) {
      final slots = List<ShelfItem?>.filled(slotsPerRow, null);
      for (final (slot, kind) in decorFor(r)) {
        slots[slot] = DecorItem(kind, r);
      }
      for (var s = 0; s < slotsPerRow && i < books.length; s++) {
        if (slots[s] == null) slots[s] = BookItem(books[i++]);
      }
      rows.add(slots);
      r++;
    }
    return rows;
  }
}

/// The skeuomorphic dark-wood bookcase holding the visible books.
class Bookshelf extends StatelessWidget {
  const Bookshelf({
    super.key,
    required this.books,
    required this.twinkle,
    required this.onOpen,
    required this.onDetails,
    this.noteCounts = const {},
    this.emptyMessage,
  });

  final List<Book> books;
  final Animation<double> twinkle;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onDetails;
  final Map<String, int> noteCounts;
  final String? emptyMessage;

  static const maxWidth = 1240.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth, maxWidth);
        final probe = ShelfLayout.compute(width, 0);
        final rows = probe.arrange(
          books,
          minRows: max(3, (constraints.maxHeight / probe.rowHeight).floor()),
        );
        final layout = ShelfLayout.compute(width, rows.length);

        final children = <Widget>[];
        for (var r = 0; r < rows.length; r++) {
          for (var s = 0; s < rows[r].length; s++) {
            final item = rows[r][s];
            if (item == null) continue;
            final left = layout.slotLeft(s);
            final top = layout.shelfSurface(r) - layout.coverHeight;
            switch (item) {
              case BookItem(:final book):
                children.add(
                  Positioned(
                    key: ValueKey(book.id),
                    left: left,
                    top: top,
                    width: layout.coverWidth,
                    height: layout.coverHeight,
                    child: _ShelfBook(
                      book: book,
                      noteCount: noteCounts[book.id] ?? 0,
                      onOpen: () => onOpen(book),
                      onDetails: () => onDetails(book),
                    ),
                  ),
                );
              case DecorItem(:final kind, :final seed):
                final decorHeight = layout.coverHeight * 0.92;
                children.add(
                  Positioned(
                    left: left - layout.gap * 0.3,
                    top: layout.shelfSurface(r) - decorHeight,
                    width: layout.coverWidth + layout.gap * 0.6,
                    height: decorHeight,
                    child: ShelfDecor(kind: kind, twinkle: twinkle, seed: seed),
                  ),
                );
            }
          }
        }

        final garlands = [
          Garland.across(
            left: ShelfLayout.frame * 0.6,
            right: width - ShelfLayout.frame * 0.6,
            y: ShelfLayout.crown * 0.55,
            segmentWidth: 230,
            sag: 22,
            seed: 3,
          ),
          for (var r = 0; r < rows.length - 1; r++)
            if (r.isOdd)
              Garland.across(
                left: ShelfLayout.frame,
                right: width - ShelfLayout.frame,
                y: layout.shelfSurface(r) + ShelfLayout.plank * 0.55,
                segmentWidth: 180,
                sag: 11,
                bulbSpacing: 30,
                seed: 11 + r,
              ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: SizedBox(
              width: width,
              height: layout.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _BookcasePainter(layout)),
                    ),
                  ),
                  ...children,
                  if (books.isEmpty && emptyMessage != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: layout.rowTop(1) + ShelfLayout.headroom,
                      height: layout.coverHeight,
                      child: Center(
                        child: Text(
                          emptyMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: HearthColors.textFaint,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: FairyLights(garlands: garlands, twinkle: twinkle),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShelfBook extends StatefulWidget {
  const _ShelfBook({
    required this.book,
    required this.noteCount,
    required this.onOpen,
    required this.onDetails,
  });

  final Book book;
  final int noteCount;
  final VoidCallback onOpen;
  final VoidCallback onDetails;

  @override
  State<_ShelfBook> createState() => _ShelfBookState();
}

class _ShelfBookState extends State<_ShelfBook> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final status = switch (book.status) {
      ReadingStatus.read => 'read',
      ReadingStatus.reading => '${(book.progress * 100).round()}% read',
      ReadingStatus.tbr => 'to be read',
    };
    // Mouse-hover tooltip only: `manual` stops the tooltip from claiming
    // the long-press that opens the details sheet on touch screens.
    final cover = Tooltip(
      message: '${book.title}\n${book.author}',
      waitDuration: const Duration(milliseconds: 700),
      triggerMode: TooltipTriggerMode.manual,
      child: AnimatedSlide(
        offset: Offset(0, _hover ? -0.04 : 0),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: BookCover(book: book, noteCount: widget.noteCount),
      ),
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${book.title} by ${book.author}, $status',
      hint: 'Long-press for details',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          onLongPress: widget.onDetails,
          onSecondaryTap: widget.onDetails,
          child: cover,
        ),
      ),
    );
  }
}

/// Paints the static wooden bookcase: back panel, frame, shelves, shadows.
class _BookcasePainter extends CustomPainter {
  _BookcasePainter(this.layout);
  final ShelfLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final w = layout.width;
    final h = layout.height;
    const f = ShelfLayout.frame;

    // Drop shadow of the whole case onto the wall.
    canvas.drawRect(
      Rect.fromLTWH(-6, 8, w + 12, h),
      Paint()
        ..color = const Color(0xAA000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Back panel: vertical boards, very dark.
    final back = Rect.fromLTWH(
      f,
      ShelfLayout.crown,
      w - 2 * f,
      h - ShelfLayout.crown - ShelfLayout.base,
    );
    const boardWidth = 96.0;
    var x = back.left;
    var seed = 100;
    while (x < back.right) {
      final board = Rect.fromLTRB(
        x,
        back.top,
        min(x + boardWidth, back.right),
        back.bottom,
      );
      paintWood(
        canvas,
        board,
        colors: const [Color(0xFF160D08), Color(0xFF1E130C), Color(0xFF130B07)],
        verticalGrain: true,
        seed: seed++,
        grainOpacity: 0.16,
        grainSpacing: 4,
      );
      canvas.drawLine(
        board.topLeft,
        board.bottomLeft,
        Paint()
          ..strokeWidth = 1.2
          ..color = const Color(0xFF070403),
      );
      x += boardWidth;
    }

    // Each cubby: shadow cast by the shelf above + vignette at the sides.
    for (var r = 0; r < layout.rows; r++) {
      final top = layout.rowTop(r);
      final cubby = Rect.fromLTRB(f, top, w - f, layout.shelfSurface(r));
      canvas.drawRect(
        Rect.fromLTWH(cubby.left, cubby.top, cubby.width, 42),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xDD000000), const Color(0x00000000)],
          ).createShader(Rect.fromLTWH(cubby.left, cubby.top, cubby.width, 42)),
      );
      for (final side in [true, false]) {
        final rect = side
            ? Rect.fromLTWH(cubby.left, cubby.top, 26, cubby.height)
            : Rect.fromLTWH(cubby.right - 26, cubby.top, 26, cubby.height);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              colors: side
                  ? [const Color(0x99000000), const Color(0x00000000)]
                  : [const Color(0x00000000), const Color(0x99000000)],
            ).createShader(rect),
        );
      }
    }

    // Shelf boards.
    for (var r = 0; r < layout.rows; r++) {
      final surface = layout.shelfSurface(r);
      // Top face (seen slightly from above).
      final topFace = Rect.fromLTWH(f, surface - 5, w - 2 * f, 5);
      canvas.drawRect(
        topFace,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241610), HearthColors.woodLight],
          ).createShader(topFace),
      );
      // Front edge.
      final front = Rect.fromLTWH(
        f - 2,
        surface,
        w - 2 * f + 4,
        ShelfLayout.plank,
      );
      paintWood(
        canvas,
        front,
        colors: const [
          HearthColors.woodLight,
          HearthColors.woodMid,
          HearthColors.wood,
          HearthColors.woodDark,
        ],
        seed: 7 + r,
        grainSpacing: 1.8,
      );
      // Highlight along the top edge of the front face (warm light).
      canvas.drawLine(
        front.topLeft,
        front.topRight,
        Paint()
          ..strokeWidth = 1
          ..color = HearthColors.glow.withValues(alpha: 0.16),
      );
      // Shadow the board casts into the cubby below.
      final shadow = Rect.fromLTWH(f, front.bottom, w - 2 * f, 16);
      canvas.drawRect(
        shadow,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ).createShader(shadow),
      );
    }

    // Side panels.
    for (final left in [0.0, w - f]) {
      final side = Rect.fromLTWH(left, 0, f, h);
      paintWood(
        canvas,
        side,
        colors: left == 0
            ? const [
                HearthColors.woodLight,
                HearthColors.woodMid,
                HearthColors.wood,
              ]
            : const [
                HearthColors.wood,
                HearthColors.woodMid,
                HearthColors.woodDark,
              ],
        verticalGrain: true,
        seed: left == 0 ? 41 : 42,
        grainSpacing: 1.6,
      );
      // Inner edge shading.
      final inner = left == 0
          ? Rect.fromLTWH(f - 3, 0, 3, h)
          : Rect.fromLTWH(left, 0, 3, h);
      canvas.drawRect(inner, Paint()..color = const Color(0x66000000));
    }

    // Crown (top board) with a lighter lip.
    final crown = Rect.fromLTWH(-4, 0, w + 8, ShelfLayout.crown);
    paintWood(
      canvas,
      crown,
      colors: const [
        HearthColors.woodLight,
        HearthColors.woodMid,
        HearthColors.wood,
        HearthColors.woodDark,
      ],
      seed: 5,
      grainSpacing: 1.8,
    );
    canvas.drawRect(
      Rect.fromLTWH(-4, 0, w + 8, 3),
      Paint()..color = const Color(0xFF6A4630),
    );
    final crownShadow = Rect.fromLTWH(f, ShelfLayout.crown, w - 2 * f, 10);
    canvas.drawRect(
      crownShadow,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEE000000), Color(0x00000000)],
        ).createShader(crownShadow),
    );

    // Plinth.
    final plinth = Rect.fromLTWH(
      -4,
      h - ShelfLayout.base,
      w + 8,
      ShelfLayout.base,
    );
    paintWood(
      canvas,
      plinth,
      colors: const [
        HearthColors.woodMid,
        HearthColors.wood,
        HearthColors.woodDark,
      ],
      seed: 9,
      grainSpacing: 1.8,
    );
    canvas.drawLine(
      plinth.topLeft,
      plinth.topRight,
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(_BookcasePainter old) =>
      old.layout.width != layout.width || old.layout.rows != layout.rows;
}
