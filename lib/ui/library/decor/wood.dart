import 'dart:math';
import 'dart:ui';

import '../../theme.dart';

/// Paints a block of dark espresso wood: a base gradient plus seeded,
/// gently wavy grain lines and the occasional knot.
void paintWood(
  Canvas canvas,
  Rect rect, {
  List<Color> colors = const [
    HearthColors.woodMid,
    HearthColors.wood,
    HearthColors.woodDark,
  ],
  bool verticalGrain = false,
  int seed = 1,
  double grainOpacity = 0.22,
  double grainSpacing = 3.2,
  bool knots = true,
}) {
  if (rect.isEmpty) return;
  final gradient = Gradient.linear(
    verticalGrain ? rect.centerLeft : rect.topCenter,
    verticalGrain ? rect.centerRight : rect.bottomCenter,
    colors,
    _evenStops(colors.length),
  );
  canvas.drawRect(rect, Paint()..shader = gradient);

  canvas.save();
  canvas.clipRect(rect);
  final rnd = Random(seed);
  final length = verticalGrain ? rect.height : rect.width;
  final across = verticalGrain ? rect.width : rect.height;
  final count = max(2, (across / grainSpacing).ceil());
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  const step = 12.0;

  for (var i = 0; i < count; i++) {
    final offset = rnd.nextDouble() * across;
    final amp = 0.3 + rnd.nextDouble() * 1.8;
    final freq = (0.6 + rnd.nextDouble() * 2.4) * 2 * pi / max(length, 1);
    final phase = rnd.nextDouble() * 2 * pi;
    final light = rnd.nextDouble() < 0.45;
    paint
      ..strokeWidth = 0.35 + rnd.nextDouble() * 0.9
      ..color = (light ? const Color(0xFF7A5238) : const Color(0xFF090504))
          .withValues(alpha: grainOpacity * (0.35 + rnd.nextDouble() * 0.65));
    final path = Path();
    for (double t = 0; t <= length + step; t += step) {
      final d = offset + sin(t * freq + phase) * amp;
      final x = verticalGrain ? rect.left + d : rect.left + t;
      final y = verticalGrain ? rect.top + t : rect.top + d;
      if (t == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  if (knots && length > 160 && across > 10) {
    final knotCount = rnd.nextInt(2) + (length > 600 ? 1 : 0);
    for (var k = 0; k < knotCount; k++) {
      final along = rnd.nextDouble() * length;
      final acr = across * (0.3 + rnd.nextDouble() * 0.4);
      final center = verticalGrain
          ? Offset(rect.left + acr, rect.top + along)
          : Offset(rect.left + along, rect.top + acr);
      final r = min(across * 0.28, 7.0);
      for (var ring = 3; ring >= 1; ring--) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: (verticalGrain ? r : r * 2.6) * ring / 2,
            height: (verticalGrain ? r * 2.6 : r) * ring / 2,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..color = const Color(0xFF0B0604).withValues(alpha: 0.35),
        );
      }
    }
  }
  canvas.restore();
}

List<double> _evenStops(int n) => [
  for (var i = 0; i < n; i++) n == 1 ? 0.0 : i / (n - 1),
];
