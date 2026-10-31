import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// The three Kindle-style tap regions laid over a reader page.
enum TapZone { previous, menu, next }

/// Stacks invisible tap regions over [child]: the left 20 % turns back, the
/// centre 60 % toggles the reader menu, the right 20 % turns forward.
///
/// The zones watch raw pointer events instead of joining the gesture arena,
/// so they never steal gestures from [child]:
/// * drags, scrolls and long presses (text selection) are not taps and are
///   ignored here;
/// * taps on something [child] treats as tappable (an inline link or
///   highlight span, or a widget showing a click cursor) are left entirely
///   to [child].
class TapZones extends StatefulWidget {
  const TapZones({super.key, required this.child, required this.onTap});

  final Widget child;

  /// Called with the zone that was tapped and the tap's global position, so
  /// the reader can still check what lies under the finger (for example a
  /// painted highlight) before acting on the zone.
  final void Function(TapZone zone, Offset globalPosition) onTap;

  static const double edgeFraction = 0.2;

  @override
  State<TapZones> createState() => _TapZonesState();
}

class _TapZonesState extends State<TapZones> {
  int? _pointer;
  TapZone? _zone;
  Offset _downPosition = Offset.zero;

  /// Fires when the pointer has been held long enough to be a long press
  /// (text selection), which then no longer counts as a tap.
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onDown(TapZone zone, PointerDownEvent e) {
    final isPrimary =
        e.kind != PointerDeviceKind.mouse || e.buttons == kPrimaryMouseButton;
    if (_pointer != null || !isPrimary) {
      // A second finger (pinch) or a non-primary mouse button: not a tap.
      _reset();
      return;
    }
    _pointer = e.pointer;
    _zone = zone;
    _downPosition = e.position;
    _holdTimer = Timer(kLongPressTimeout, _reset);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if ((e.position - _downPosition).distance > kTouchSlop) _reset();
  }

  void _onUp(PointerUpEvent e) {
    final zone = _zone;
    final isTap = e.pointer == _pointer && zone != null;
    _reset();
    if (isTap && !_hitsTappable(e.position)) widget.onTap(zone, e.position);
  }

  void _reset() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pointer = null;
    _zone = null;
  }

  /// Whether [child] has its own tap target at [globalPosition].
  bool _hitsTappable(Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is TextSpan && target.recognizer != null) return true;
      if (target is RenderMouseRegion &&
          target.cursor == SystemMouseCursors.click) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const edge = TapZones.edgeFraction;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _zoneWidget(TapZone.previous, edge),
            _zoneWidget(TapZone.menu, 1 - 2 * edge),
            _zoneWidget(TapZone.next, edge),
          ],
        ),
      ],
    );
  }

  Widget _zoneWidget(TapZone zone, double fraction) => Expanded(
    flex: (fraction * 100).round(),
    child: Listener(
      // Translucent: hit-testing continues to the page underneath, which
      // receives every pointer event exactly as if the zones were absent.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _onDown(zone, e),
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _reset(),
    ),
  );
}
