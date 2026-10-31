import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Strict dark-mode frame shared by the PDF and EPUB readers: black page,
/// a slim top bar and an optional bottom control row.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.visible = true,
    this.progress,
    this.drawer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final Widget? bottom;
  final bool visible;
  final double? progress;
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HearthColors.readerBackground,
      drawer: drawer,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: visible
                  ? _TopBar(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                      hasDrawer: drawer != null,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (progress != null)
              LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 1.5,
                backgroundColor: const Color(0xFF151311),
                color: HearthColors.accent.withValues(alpha: 0.7),
              ),
            Expanded(child: child),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: visible && bottom != null
                  ? SafeArea(
                      top: false,
                      child: Container(
                        color: const Color(0xFF0A0908),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                        child: bottom,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.hasDrawer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool hasDrawer;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0908),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          const BackButton(),
          if (hasDrawer)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Contents',
                icon: const Icon(Icons.toc),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HearthColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Slider for jumping between pages (or chapters).
class PageScrubber extends StatefulWidget {
  const PageScrubber({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.label,
    this.min = 1,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String Function(int) label;

  @override
  State<PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<PageScrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final shown = (_dragging ?? widget.value.toDouble()).clamp(
      widget.min.toDouble(),
      widget.max.toDouble(),
    );
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            widget.label(shown.round()),
            style: const TextStyle(color: HearthColors.textMuted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            value: shown,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v.round());
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${widget.max}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: HearthColors.textFaint, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
