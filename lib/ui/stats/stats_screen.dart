import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/library_controller.dart';
import '../../services/reading_stats.dart';
import '../app_scope.dart';
import '../library/book_cover.dart';
import '../theme.dart';

/// Reading dashboard: pages read and books finished per day, week, month,
/// semester or year, with a bar chart and per-book breakdown.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.now});

  /// Overrides "today" (tests).
  final DateTime? now;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final LibraryController _library = AppScope.read(context);
  late DateTime _now = widget.now ?? DateTime.now();
  late StatsRange _range = StatsRange.containing(StatsPeriod.month, _now);
  Future<ReadingStats>? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stats ??= _load();
  }

  Future<ReadingStats> _load() async {
    final range = _range;
    final log = await _library.readingLog(range.start, range.end);
    return ReadingStats.compute(range, log, _library.books);
  }

  void _select(StatsRange range) {
    setState(() {
      _now = widget.now ?? DateTime.now();
      _range = range;
      _stats = _load();
    });
  }

  bool get _isCurrent => _range.contains(_now);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading stats')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<StatsPeriod>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                    segments: [
                      for (final p in StatsPeriod.values)
                        ButtonSegment(value: p, label: Text(p.label)),
                    ],
                    selected: {_range.period},
                    onSelectionChanged: (s) =>
                        _select(StatsRange.containing(s.single, _now)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous ${_range.period.label.toLowerCase()}',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _select(_range.previous),
                    ),
                    Expanded(
                      child: Text(
                        _range.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!_isCurrent)
                      TextButton(
                        onPressed: () =>
                            _select(StatsRange.containing(_range.period, _now)),
                        child: const Text('Today'),
                      ),
                    IconButton(
                      tooltip: 'Next ${_range.period.label.toLowerCase()}',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _range.end.isAfter(_now)
                          ? null
                          : () => _select(_range.next),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<ReadingStats>(
                  future: _stats,
                  builder: (context, snap) {
                    final stats = snap.data;
                    if (stats == null || stats.range != _range) {
                      return const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _StatsBody(stats: stats, now: _now);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats, required this.now});

  final ReadingStats stats;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final avg = stats.averagePerDay(now);
    final isDay = stats.range.period == StatsPeriod.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 10,
            runSpacing: 10,
            // Two tiles per row on phones, four across on wider screens.
            children: [
              for (final tile in [
                _StatTile(label: 'Pages read', value: _fmt(stats.pages)),
                _StatTile(
                  label: 'Books finished',
                  value: _fmt(stats.finished.length),
                ),
                if (!isDay) ...[
                  _StatTile(
                    label: 'Pages / day',
                    value: avg >= 10 || avg == 0
                        ? _fmt(avg.round())
                        : avg.toStringAsFixed(1),
                  ),
                  _StatTile(
                    label: 'Reading days',
                    value: '${stats.activeDays}',
                  ),
                ],
              ])
                SizedBox(
                  width: c.maxWidth >= 600
                      ? (c.maxWidth - 30) / 4
                      : (c.maxWidth - 10) / 2,
                  child: tile,
                ),
            ],
          ),
        ),
        if (!isDay) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Pages read'),
          const SizedBox(height: 8),
          _PagesChart(stats: stats, now: now),
        ],
        const SizedBox(height: 24),
        _SectionTitle('Finished · ${stats.finished.length}'),
        if (stats.finished.isEmpty)
          const _Empty('No books finished in this period.')
        else
          for (final b in stats.finished)
            _BookRow(book: b, trailing: _shortDate(b.finishedAt!)),
        const SizedBox(height: 24),
        _SectionTitle('Pages by book · ${stats.byBook.length}'),
        if (stats.byBook.isEmpty)
          const _Empty('Nothing read in this period yet.')
        else
          for (final e in stats.byBook)
            _BookRow(
              book: e.book,
              trailing: '${_fmt(e.pages)} p',
              share: stats.pages == 0 ? 0 : e.pages / stats.pages,
            ),
        const SizedBox(height: 16),
        const Text(
          'EPUB pages are estimated from the book\'s length. '
          'Jumps through the contents or slider are not counted.',
          style: TextStyle(color: HearthColors.textFaint, fontSize: 12),
        ),
      ],
    );
  }
}

String _fmt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: HearthColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HearthColors.outline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: HearthColors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: HearthColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: HearthColors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: const TextStyle(color: HearthColors.textFaint)),
  );
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.trailing, this.share});

  final Book book;
  final String trailing;

  /// Fraction of the period's pages, drawn as a thin bar under the title.
  final double? share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Generated covers are laid out for shelf size; draw at that size
          // and scale down so their titles don't overflow.
          SizedBox(
            width: 30,
            height: 44,
            child: FittedBox(
              child: SizedBox(
                width: 90,
                height: 132,
                child: BookCover(book: book, showStatus: false),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: HearthColors.text),
                ),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HearthColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
                if (share != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 3,
                      backgroundColor: HearthColors.surfaceHigh,
                      color: HearthColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trailing,
            style: const TextStyle(
              color: HearthColors.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-series column chart of pages per bucket. One series, so no legend:
/// the section title names it. Bars carry the accent; all text stays in
/// text colours. Hover (desktop) or tap (touch) shows a bar's exact value.
class _PagesChart extends StatelessWidget {
  const _PagesChart({required this.stats, required this.now});

  final ReadingStats stats;
  final DateTime now;

  static const _chartHeight = 160.0;
  static const _axisWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final buckets = stats.range.buckets;
    final values = stats.bucketPages;
    final maxValue = values.fold<int>(0, max);
    final top = _niceCeiling(maxValue);
    final maxIndex = maxValue == 0 ? -1 : values.indexOf(maxValue);
    final labelEvery = buckets.length > 14 ? 5 : 1;
    const axisStyle = TextStyle(color: HearthColors.textFaint, fontSize: 11);

    return SizedBox(
      height: _chartHeight + 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Y-axis ticks: 0, half, top.
          SizedBox(
            width: _axisWidth,
            height: _chartHeight + 24,
            child: Stack(
              children: [
                for (final f in const [0.0, 0.5, 1.0])
                  Positioned(
                    right: 6,
                    top: 16 + _chartHeight * (1 - f) - 7,
                    child: Text(_fmt((top * f).round()), style: axisStyle),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: _chartHeight + 16,
                  child: Stack(
                    children: [
                      // Hairline gridlines.
                      for (final f in const [0.0, 0.5, 1.0])
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 16 + _chartHeight * (1 - f),
                          child: Container(
                            height: 1,
                            color: f == 0
                                ? HearthColors.outline
                                : HearthColors.surfaceHigh,
                          ),
                        ),
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < buckets.length; i++)
                              Expanded(
                                child: _Bar(
                                  value: values[i],
                                  fraction: top == 0 ? 0 : values[i] / top,
                                  height: _chartHeight,
                                  tooltip:
                                      '${buckets[i].label}: ${_fmt(values[i])} pages',
                                  showValue: i == maxIndex,
                                  future: buckets[i].start.isAfter(now),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < buckets.length; i++)
                      Expanded(
                        child: Text(
                          _axisLabel(buckets, i, labelEvery),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          softWrap: false,
                          style: axisStyle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _axisLabel(List<StatsRange> buckets, int i, int every) {
    final b = buckets[i];
    if (stats.range.period == StatsPeriod.week) {
      return '${b.weekdayInitial} ${b.start.day}';
    }
    if (b.period == StatsPeriod.day && i % every != 0 && i != 0) return '';
    return b.shortLabel;
  }

  /// Rounds up to a clean axis maximum (1, 2, 5 × 10^n), at least 10.
  static int _niceCeiling(int v) {
    if (v <= 10) return 10;
    var magnitude = 1;
    while (magnitude * 10 <= v) {
      magnitude *= 10;
    }
    for (final step in const [1, 2, 5, 10]) {
      if (step * magnitude >= v) return step * magnitude;
    }
    return 10 * magnitude;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.fraction,
    required this.height,
    required this.tooltip,
    required this.showValue,
    required this.future,
  });

  final int value;
  final double fraction;
  final double height;
  final String tooltip;
  final bool showValue;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final barHeight = value == 0 ? 0.0 : max(2.0, height * fraction);
    return Tooltip(
      message: future ? '' : tooltip,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: const Duration(milliseconds: 150),
      // The whole column is the hit target, not just the (maybe tiny) bar.
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  _fmt(value),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: HearthColors.textMuted,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 24),
              child: Container(
                height: barHeight,
                decoration: const BoxDecoration(
                  color: HearthColors.accent,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
