import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../theme.dart';

/// A string of lights draped between [anchors], sagging by [sag] pixels
/// between each pair.
class Garland {
  const Garland({
    required this.anchors,
    this.sag = 18,
    this.bulbSpacing = 26,
    this.seed = 7,
  });

  final List<Offset> anchors;
  final double sag;
  final double bulbSpacing;
  final int seed;

  /// Evenly spaced anchors along a horizontal line.
  factory Garland.across({
    required double left,
    required double right,
    required double y,
    double segmentWidth = 240,
    double sag = 18,
    double bulbSpacing = 26,
    int seed = 7,
  }) {
    final width = right - left;
    final segments = max(1, (width / segmentWidth).round());
    return Garland(
      anchors: [
        for (var i = 0; i <= segments; i++)
          Offset(left + width * i / segments, y),
      ],
      sag: sag,
      bulbSpacing: bulbSpacing,
      seed: seed,
    );
  }

  Path get path {
    final path = Path()..moveTo(anchors.first.dx, anchors.first.dy);
    for (var i = 0; i < anchors.length - 1; i++) {
      final a = anchors[i];
      final b = anchors[i + 1];
      // A quadratic control point 2*sag below the midpoint makes the curve
      // dip by exactly `sag`, close enough to a catenary.
      final control = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 + sag * 2);
      path.quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
    }
    return path;
  }
}

class _Bulb {
  _Bulb(this.position, this.phase, this.speed, this.size, this.tint);
  final Offset position;
  final double phase;
  final int speed;
  final double size;
  final Color tint;
}

/// Paints warm, softly twinkling fairy lights.
///
/// [twinkle] runs 0→1 repeatedly; each bulb pulses an integer number of times
/// per cycle so the loop is seamless.
class FairyLightsPainter extends CustomPainter {
  FairyLightsPainter({
    required this.garlands,
    required this.twinkle,
    this.intensity = 1,
  }) : super(repaint: twinkle);

  final List<Garland> garlands;
  final Animation<double> twinkle;
  final double intensity;

  late final List<(Path, List<_Bulb>)> _strings = [
    for (final g in garlands) (g.path, _bulbsFor(g)),
  ];

  static const _tints = [
    HearthColors.glow,
    Color(0xFFFFB45A),
    Color(0xFFFFD99A),
  ];

  static List<_Bulb> _bulbsFor(Garland g) {
    final rnd = Random(g.seed);
    final bulbs = <_Bulb>[];
    for (final metric in g.path.computeMetrics()) {
      for (
        double d = g.bulbSpacing / 2;
        d < metric.length;
        d += g.bulbSpacing * (0.85 + rnd.nextDouble() * 0.3)
      ) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        bulbs.add(
          _Bulb(
            tangent.position,
            rnd.nextDouble() * 2 * pi,
            1 + rnd.nextInt(3),
            0.8 + rnd.nextDouble() * 0.45,
            _tints[rnd.nextInt(_tints.length)],
          ),
        );
      }
    }
    return bulbs;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = twinkle.value;
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF2B2420);
    final wash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 36
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
      ..color = HearthColors.glow.withValues(alpha: 0.045 * intensity);

    for (final (path, bulbs) in _strings) {
      // Warm light spilling onto the wall and wood behind the string.
      canvas.drawPath(path, wash);
      canvas.drawPath(path, wire);

      for (final b in bulbs) {
        final pulse = 0.5 + 0.5 * sin(2 * pi * t * b.speed + b.phase);
        final brightness = (0.55 + 0.45 * pulse) * intensity;
        final glowRadius = 13.0 * b.size;
        canvas.drawCircle(
          b.position,
          glowRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              b.position,
              glowRadius,
              [
                b.tint.withValues(alpha: 0.55 * brightness),
                b.tint.withValues(alpha: 0.16 * brightness),
                b.tint.withValues(alpha: 0),
              ],
              const [0, 0.35, 1],
            ),
        );
        // Little bulb body hanging from the wire.
        final bulbCenter = b.position.translate(0, 2.2);
        canvas.drawRect(
          Rect.fromCenter(center: b.position, width: 2.4, height: 2),
          Paint()..color = const Color(0xFF1C1714),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: bulbCenter,
            width: 3.6 * b.size,
            height: 4.8 * b.size,
          ),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF8A5A2A),
              const Color(0xFFFFF1D0),
              brightness.clamp(0, 1),
            )!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FairyLightsPainter old) =>
      old.garlands != garlands || old.intensity != intensity;
}

/// Convenience widget: fairy lights laid over its child-sized area.
class FairyLights extends StatelessWidget {
  const FairyLights({
    super.key,
    required this.garlands,
    required this.twinkle,
    this.intensity = 1,
  });

  final List<Garland> garlands;
  final Animation<double> twinkle;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: FairyLightsPainter(
            garlands: garlands,
            twinkle: twinkle,
            intensity: intensity,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}
