import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../theme.dart';

/// Front-facing book cover with hardcover shading and status indicators.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.showStatus = true,
    this.noteCount = 0,
  });

  final Book book;
  final bool showStatus;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    final Widget art = coverPath != null
        ? Image.file(
            File(coverPath),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => GeneratedCover(book: book),
          )
        : GeneratedCover(book: book);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 10,
                offset: Offset(3, 4),
              ),
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 2,
                offset: Offset(1, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(3),
              bottomRight: Radius.circular(3),
              topLeft: Radius.circular(1.5),
              bottomLeft: Radius.circular(1.5),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                art,
                // Hardcover hinge near the spine + soft overall sheen.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x66000000),
                        Color(0x22FFFFFF),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x26000000),
                      ],
                      stops: [0, 0.045, 0.09, 0.85, 1],
                    ),
                  ),
                ),
                // Dim covers so bright art doesn't glare in the dark; PDF
                // "covers" are usually white first pages, so dim them more.
                ColoredBox(
                  color: book.format == BookFormat.pdf && coverPath != null
                      ? const Color(0x47000000)
                      : const Color(0x14000000),
                ),
                if (showStatus && book.status == ReadingStatus.reading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ProgressStrip(progress: book.completion),
                  ),
                if (showStatus && book.status == ReadingStatus.reading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: w * 0.08,
                    child: Center(
                      child: CompletionBadge(
                        percent: book.completionPercent,
                        fontSize: (w * 0.12).clamp(9, 14),
                      ),
                    ),
                  ),
                if (showStatus && book.status == ReadingStatus.read)
                  Positioned(
                    top: w * 0.05,
                    right: w * 0.05,
                    child: _ReadBadge(size: (w * 0.2).clamp(14, 22)),
                  ),
                if (showStatus && noteCount > 0)
                  Positioned(
                    top: w * 0.05,
                    left: w * 0.1,
                    child: _NotesRibbon(width: (w * 0.11).clamp(7, 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dark, high-contrast pill showing reading completion, e.g. "45%".
class CompletionBadge extends StatelessWidget {
  const CompletionBadge({super.key, required this.percent, this.fontSize = 12});

  final int percent;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.6,
        vertical: fontSize * 0.2,
      ),
      decoration: BoxDecoration(
        color: const Color(0xC7000000),
        borderRadius: BorderRadius.circular(fontSize),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      color: const Color(0xCC000000),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0.02, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: HearthColors.accent,
            boxShadow: [
              BoxShadow(
                color: HearthColors.glow.withValues(alpha: 0.6),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadBadge extends StatelessWidget {
  const _ReadBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Read',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: HearthColors.readGreen,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF0E2412), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 4)],
        ),
        child: Icon(
          Icons.check_rounded,
          size: size * 0.72,
          color: const Color(0xFF0B1A0E),
        ),
      ),
    );
  }
}

/// A small fabric bookmark ribbon hinting that the book has notes.
class _NotesRibbon extends StatelessWidget {
  const _NotesRibbon({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 2.2),
      painter: _RibbonPainter(),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -size.height * 0.4)
      ..lineTo(size.width, -size.height * 0.4)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.78)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0xFF000000), 2, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFF9E3B32));
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => false;
}

/// A tasteful cloth-bound cover for books without cover art.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.book});
  final Book book;

  static const _cloths = [
    (Color(0xFF4E1F1F), Color(0xFFD9B77A)), // oxblood + gold
    (Color(0xFF1E3540), Color(0xFFC9B48A)), // deep teal
    (Color(0xFF2A3A2A), Color(0xFFD1C08F)), // forest
    (Color(0xFF3A2F4A), Color(0xFFD6BE8E)), // plum
    (Color(0xFF4A3A22), Color(0xFFE8D4A6)), // ochre
    (Color(0xFF26262E), Color(0xFFC0B49C)), // slate
  ];

  @override
  Widget build(BuildContext context) {
    final hash = book.title.codeUnits.fold<int>(7, (h, c) => (h * 31 + c));
    final (cloth, ink) = _cloths[hash.abs() % _cloths.length];
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(cloth, Colors.white, 0.06)!,
                cloth,
                Color.lerp(cloth, Colors.black, 0.35)!,
              ],
            ),
          ),
          padding: EdgeInsets.fromLTRB(w * 0.14, w * 0.12, w * 0.08, w * 0.1),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: ink.withValues(alpha: 0.6), width: 0.8),
            ),
            padding: EdgeInsets.all(w * 0.06),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      book.title,
                      textAlign: TextAlign.center,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontFamily: kSerifFont,
                        fontWeight: FontWeight.w600,
                        fontSize: (w * 0.115).clamp(9, 16),
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: w * 0.2,
                  height: 0.8,
                  color: ink.withValues(alpha: 0.6),
                ),
                SizedBox(height: w * 0.04),
                Text(
                  book.author,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.85),
                    fontSize: (w * 0.075).clamp(7, 11),
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: w * 0.03),
                Text(
                  book.format.name.toUpperCase(),
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.55),
                    fontSize: (w * 0.06).clamp(6, 9),
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
