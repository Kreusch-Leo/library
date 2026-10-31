import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../theme.dart';

enum DecorKind { plant, bookStack, lightJar }

/// A decorative object standing on a shelf. Painted to fill its box, sitting
/// on the box's bottom edge (the shelf surface).
class ShelfDecor extends StatelessWidget {
  const ShelfDecor({
    super.key,
    required this.kind,
    required this.twinkle,
    this.seed = 0,
  });

  final DecorKind kind;
  final Animation<double> twinkle;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final CustomPainter painter = switch (kind) {
      DecorKind.plant => PottedPlantPainter(seed: seed),
      DecorKind.bookStack => BookStackPainter(seed: seed, flicker: twinkle),
      DecorKind.lightJar => LightJarPainter(seed: seed, twinkle: twinkle),
    };
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: painter, size: Size.infinite),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Potted plant (trailing pothos in a dark ceramic pot).

class PottedPlantPainter extends CustomPainter {
  PottedPlantPainter({this.seed = 0});
  final int seed;

  static const _leafColors = [
    Color(0xFF2E5B38),
    Color(0xFF3B6E45),
    Color(0xFF24472C),
    Color(0xFF4A7D4F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(31 + seed);
    final w = size.width;
    final h = size.height;
    final potW = w * 0.62;
    final potH = h * 0.30;
    final potTop = h - potH;
    final cx = w / 2;

    // Contact shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h - 1), width: potW * 1.1, height: 6),
      Paint()
        ..color = const Color(0xCC000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Leaves behind the pot rim (upright growth).
    final stemBase = Offset(cx, potTop + 4);
    for (var i = 0; i < 9; i++) {
      final angle = -pi / 2 + (rnd.nextDouble() - 0.5) * 1.9;
      final len = h * (0.32 + rnd.nextDouble() * 0.38);
      final tip = stemBase + Offset(cos(angle) * len, sin(angle) * len);
      final ctrl =
          stemBase +
          Offset(
            cos(angle) * len * 0.5 + (rnd.nextDouble() - 0.5) * 14,
            sin(angle) * len * 0.5,
          );
      canvas.drawPath(
        Path()
          ..moveTo(stemBase.dx, stemBase.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF1F3A24),
      );
      _leaf(
        canvas,
        tip,
        angle + (rnd.nextDouble() - 0.5) * 0.6,
        w * (0.16 + rnd.nextDouble() * 0.08),
        _leafColors[rnd.nextInt(4)],
      );
    }

    // Pot body: a slightly tapered ceramic pot with a rim.
    final pot = Path()
      ..moveTo(cx - potW / 2, potTop + potH * 0.16)
      ..lineTo(cx + potW / 2, potTop + potH * 0.16)
      ..lineTo(cx + potW * 0.40, h - 1)
      ..quadraticBezierTo(cx, h + 2, cx - potW * 0.40, h - 1)
      ..close();
    canvas.drawPath(
      pot,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - potW / 2, 0),
          Offset(cx + potW / 2, 0),
          const [Color(0xFF2A2725), Color(0xFF45403B), Color(0xFF1B1917)],
          const [0, 0.35, 1],
        ),
    );
    final rim = Rect.fromLTWH(cx - potW / 2 - 2, potTop, potW + 4, potH * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rim, const Radius.circular(2)),
      Paint()
        ..shader = ui.Gradient.linear(
          rim.centerLeft,
          rim.centerRight,
          const [Color(0xFF34302C), Color(0xFF55504A), Color(0xFF221F1C)],
          const [0, 0.35, 1],
        ),
    );
    // Warm reflection of the fairy lights on the glaze.
    canvas.drawLine(
      Offset(cx - potW * 0.28, potTop + potH * 0.3),
      Offset(cx - potW * 0.24, h - potH * 0.12),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = HearthColors.glow.withValues(alpha: 0.18),
    );

    // Trailing vines spilling over the rim and down the shelf edge.
    for (var v = 0; v < 2; v++) {
      final side = v == 0 ? -1.0 : 1.0;
      final start = Offset(cx + side * potW * 0.42, potTop + 2);
      final end = Offset(
        cx + side * potW * (0.62 + rnd.nextDouble() * 0.2),
        h + h * 0.18,
      );
      final vine = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + side * 10,
          start.dy - 6,
          end.dx + side * 6,
          (start.dy + end.dy) / 2,
          end.dx,
          end.dy,
        );
      canvas.drawPath(
        vine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = const Color(0xFF1F3A24),
      );
      for (final metric in vine.computeMetrics()) {
        for (double d = 6; d < metric.length; d += 9 + rnd.nextDouble() * 4) {
          final tangent = metric.getTangentForOffset(d)!;
          final dir = tangent.angle;
          final alt = (d ~/ 9).isEven ? 1 : -1;
          _leaf(
            canvas,
            tangent.position,
            -dir + alt * 1.1 + pi / 2 * side,
            w * 0.12,
            _leafColors[rnd.nextInt(4)],
          );
        }
      }
    }
  }

  void _leaf(Canvas canvas, Offset at, double angle, double len, Color color) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle + pi / 2);
    final leaf = Path()
      ..moveTo(0, 0)
      ..cubicTo(len * 0.55, -len * 0.15, len * 0.45, -len * 0.85, 0, -len)
      ..cubicTo(-len * 0.45, -len * 0.85, -len * 0.55, -len * 0.15, 0, 0)
      ..close();
    canvas.drawPath(leaf, Paint()..color = color);
    canvas.drawLine(
      Offset.zero,
      Offset(0, -len * 0.85),
      Paint()
        ..strokeWidth = 0.6
        ..color = const Color(0x3399D19A),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PottedPlantPainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------
// A horizontal stack of books with a small candle on top.

class BookStackPainter extends CustomPainter {
  BookStackPainter({this.seed = 0, required this.flicker})
    : super(repaint: flicker);

  final int seed;
  final Animation<double> flicker;

  static const _bookColors = [
    Color(0xFF5A2626),
    Color(0xFF26404D),
    Color(0xFF5E4D2E),
    Color(0xFF3A3150),
    Color(0xFF2F4A35),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(97 + seed);
    final w = size.width;
    final h = size.height;
    var y = h;
    final count = 3 + rnd.nextInt(2);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h - 1), width: w * 1.05, height: 6),
      Paint()
        ..color = const Color(0xCC000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    for (var i = 0; i < count; i++) {
      final bookH = h * (0.075 + rnd.nextDouble() * 0.035);
      final bookW = w * (0.80 + rnd.nextDouble() * 0.2);
      final left = (w - bookW) / 2 + (rnd.nextDouble() - 0.5) * w * 0.1;
      final rect = Rect.fromLTWH(left, y - bookH, bookW, bookH);
      final color = _bookColors[(i + seed) % _bookColors.length];
      // Page block on the right, spine on the left.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            [
              Color.lerp(color, const Color(0xFFFFFFFF), 0.08)!,
              color,
              Color.lerp(color, const Color(0xFF000000), 0.45)!,
            ],
            const [0, 0.5, 1],
          ),
      );
      final pages = Rect.fromLTWH(
        rect.right - 3,
        rect.top + 1.5,
        2.5,
        rect.height - 3,
      );
      canvas.drawRect(pages, Paint()..color = const Color(0xFFBFB3A0));
      for (final fx in [0.12, 0.88]) {
        final x = rect.left + rect.width * fx;
        canvas.drawLine(
          Offset(x, rect.top + 1),
          Offset(x, rect.bottom - 1),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0x66D4B26A),
        );
      }
      y -= bookH;
    }

    // Candle.
    final candleW = w * 0.24;
    final candleH = h * 0.16;
    final candle = Rect.fromLTWH(
      w / 2 - candleW / 2,
      y - candleH,
      candleW,
      candleH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(candle, const Radius.circular(2)),
      Paint()
        ..shader = ui.Gradient.linear(
          candle.centerLeft,
          candle.centerRight,
          const [Color(0xFFCFC2A8), Color(0xFFF3E6CB), Color(0xFFA89A80)],
          const [0, 0.4, 1],
        ),
    );
    final wickTop = Offset(w / 2, candle.top - 3);
    canvas.drawLine(
      Offset(w / 2, candle.top),
      wickTop,
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF221A12),
    );

    // Flame flicker from a few summed sines (seamless over the loop).
    final t = flicker.value * 2 * pi;
    final f =
        0.85 +
        0.08 * sin(t * 7 + seed) +
        0.05 * sin(t * 13 + 1.3) +
        0.03 * sin(t * 29 + 2.1);
    final sway = 0.8 * sin(t * 5 + seed);
    final flameH = h * 0.11 * f;
    final flameW = candleW * 0.42;
    final base = wickTop.translate(0, 2);

    canvas.drawCircle(
      base.translate(0, -flameH * 0.4),
      h * 0.35,
      Paint()
        ..shader = ui.Gradient.radial(
          base.translate(0, -flameH * 0.4),
          h * 0.35,
          [
            HearthColors.glow.withValues(alpha: 0.28 * f),
            HearthColors.glow.withValues(alpha: 0.06 * f),
            HearthColors.glow.withValues(alpha: 0),
          ],
          const [0, 0.4, 1],
        ),
    );
    final flame = Path()
      ..moveTo(base.dx - flameW / 2, base.dy)
      ..quadraticBezierTo(
        base.dx - flameW / 2,
        base.dy - flameH * 0.55,
        base.dx + sway,
        base.dy - flameH,
      )
      ..quadraticBezierTo(
        base.dx + flameW / 2,
        base.dy - flameH * 0.55,
        base.dx + flameW / 2,
        base.dy,
      )
      ..close();
    canvas.drawPath(
      flame,
      Paint()
        ..shader = ui.Gradient.linear(
          base,
          base.translate(0, -flameH),
          const [Color(0xFFFFF4D6), Color(0xFFFFC56E), Color(0x00FF8A3D)],
          const [0, 0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(BookStackPainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------
// A mason jar filled with tiny twinkling lights.

class LightJarPainter extends CustomPainter {
  LightJarPainter({this.seed = 0, required this.twinkle})
    : super(repaint: twinkle);

  final int seed;
  final Animation<double> twinkle;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(53 + seed);
    final w = size.width;
    final h = size.height;
    final jarW = w * 0.62;
    final jarH = h * 0.46;
    final jar = Rect.fromLTWH((w - jarW) / 2, h - jarH, jarW, jarH);
    final body = RRect.fromRectAndCorners(
      jar.deflate(1),
      topLeft: const Radius.circular(9),
      topRight: const Radius.circular(9),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    final t = twinkle.value;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h - 1),
        width: jarW * 1.2,
        height: 6,
      ),
      Paint()
        ..color = const Color(0xCC000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Light cast around the jar.
    canvas.drawCircle(
      jar.center,
      jarW * 1.1,
      Paint()
        ..shader = ui.Gradient.radial(jar.center, jarW * 1.1, [
          HearthColors.glow.withValues(alpha: 0.22),
          HearthColors.glow.withValues(alpha: 0),
        ]),
    );

    // Glass.
    canvas.drawRRect(
      body,
      Paint()..color = const Color(0xFFFFE9C2).withValues(alpha: 0.06),
    );

    // Tiny lights inside, on a looping wire.
    canvas.save();
    canvas.clipRRect(body);
    final wire = Path();
    final n = 14;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      points.add(
        Offset(
          jar.left + 5 + rnd.nextDouble() * (jarW - 10),
          jar.top + 10 + rnd.nextDouble() * (jarH - 14),
        ),
      );
    }
    wire.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < n; i++) {
      final prev = points[i - 1];
      final p = points[i];
      wire.quadraticBezierTo(
        (prev.dx + p.dx) / 2 + 6,
        (prev.dy + p.dy) / 2 - 6,
        p.dx,
        p.dy,
      );
    }
    canvas.drawPath(
      wire,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(0x55A08060),
    );
    for (var i = 0; i < n; i++) {
      final speed = 1 + (i * 7 + seed) % 3;
      final pulse =
          0.5 + 0.5 * sin(2 * pi * t * speed + rnd.nextDouble() * 2 * pi);
      final b = 0.5 + 0.5 * pulse;
      canvas.drawCircle(
        points[i],
        6,
        Paint()
          ..shader = ui.Gradient.radial(points[i], 6, [
            HearthColors.glow.withValues(alpha: 0.7 * b),
            HearthColors.glow.withValues(alpha: 0),
          ]),
      );
      canvas.drawCircle(
        points[i],
        1.2,
        Paint()..color = const Color(0xFFFFF3D6),
      );
    }
    canvas.restore();

    // Glass edges and highlights.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0x55E8D8C0),
    );
    canvas.drawLine(
      Offset(jar.left + 5, jar.top + 12),
      Offset(jar.left + 5, jar.bottom - 8),
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x33FFFFFF),
    );
    // Lid.
    final lid = Rect.fromLTWH(
      jar.left + jarW * 0.12,
      jar.top - 7,
      jarW * 0.76,
      8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lid, const Radius.circular(1.5)),
      Paint()
        ..shader = ui.Gradient.linear(
          lid.centerLeft,
          lid.centerRight,
          const [Color(0xFF6B5432), Color(0xFFB08A50), Color(0xFF4A3920)],
          const [0, 0.4, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(LightJarPainter old) => old.seed != seed;
}
