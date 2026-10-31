import '../data/models.dart';

/// Time spans the reading dashboard can summarise.
enum StatsPeriod {
  day('Day'),
  week('Week'),
  month('Month'),
  semester('Semester'),
  year('Year');

  const StatsPeriod(this.label);
  final String label;
}

/// A calendar range [start, end) of one [period], e.g. "March 2026".
class StatsRange {
  const StatsRange._(this.period, this.start, this.end);

  /// The range of [period] that contains [date]. Weeks start on Monday;
  /// semesters are January–June and July–December.
  factory StatsRange.containing(StatsPeriod period, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return switch (period) {
      StatsPeriod.day => StatsRange._(
        period,
        d,
        DateTime(d.year, d.month, d.day + 1),
      ),
      StatsPeriod.week => () {
        final start = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        return StatsRange._(
          period,
          start,
          DateTime(start.year, start.month, start.day + 7),
        );
      }(),
      StatsPeriod.month => StatsRange._(
        period,
        DateTime(d.year, d.month),
        DateTime(d.year, d.month + 1),
      ),
      StatsPeriod.semester => () {
        final first = d.month <= 6 ? 1 : 7;
        return StatsRange._(
          period,
          DateTime(d.year, first),
          DateTime(d.year, first + 6),
        );
      }(),
      StatsPeriod.year => StatsRange._(
        period,
        DateTime(d.year),
        DateTime(d.year + 1),
      ),
    };
  }

  final StatsPeriod period;
  final DateTime start;
  final DateTime end;

  StatsRange get previous => StatsRange.containing(
    period,
    DateTime(start.year, start.month, start.day - 1),
  );
  StatsRange get next => StatsRange.containing(period, end);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// Number of calendar days in the range.
  int get dayCount => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

  /// Chart buckets: hours make no sense (no time-of-day data), so a day is a
  /// single bucket, weeks and months are split by day, longer spans by month.
  List<StatsRange> get buckets => switch (period) {
    StatsPeriod.day => [this],
    StatsPeriod.week || StatsPeriod.month => [
      for (var i = 0; i < dayCount; i++)
        StatsRange.containing(
          StatsPeriod.day,
          DateTime(start.year, start.month, start.day + i),
        ),
    ],
    StatsPeriod.semester || StatsPeriod.year => [
      for (
        var m = DateTime(start.year, start.month);
        m.isBefore(end);
        m = DateTime(m.year, m.month + 1)
      )
        StatsRange.containing(StatsPeriod.month, m),
    ],
  };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Heading for the range, e.g. "Mar 2026" or "Jan – Jun 2026".
  String get label {
    final last = DateTime(end.year, end.month, end.day - 1);
    return switch (period) {
      StatsPeriod.day =>
        '${_weekdays[start.weekday - 1]} ${start.day} ${_months[start.month - 1]} ${start.year}',
      StatsPeriod.week =>
        start.month == last.month
            ? '${start.day} – ${last.day} ${_months[last.month - 1]} ${last.year}'
            : '${start.day} ${_months[start.month - 1]} – ${last.day} ${_months[last.month - 1]} ${last.year}',
      StatsPeriod.month => '${_months[start.month - 1]} ${start.year}',
      StatsPeriod.semester =>
        '${_months[start.month - 1]} – ${_months[last.month - 1]} ${start.year}',
      StatsPeriod.year => '${start.year}',
    };
  }

  /// Short axis label when this range is used as a chart bucket.
  String get shortLabel => switch (period) {
    StatsPeriod.day => '${start.day}',
    StatsPeriod.month => _months[start.month - 1],
    _ => label,
  };

  String get weekdayInitial => _weekdays[start.weekday - 1].substring(0, 1);

  @override
  bool operator ==(Object other) =>
      other is StatsRange && other.period == period && other.start == start;

  @override
  int get hashCode => Object.hash(period, start);
}

/// Pages read in one book within a range.
typedef BookPages = ({Book book, int pages});

/// Everything the dashboard shows for one range.
class ReadingStats {
  ReadingStats._({
    required this.range,
    required this.pages,
    required this.bucketPages,
    required this.finished,
    required this.byBook,
    required this.activeDays,
  });

  /// Aggregates [log] (entries for [range]) and the [books] finished in it.
  factory ReadingStats.compute(
    StatsRange range,
    List<ReadingLogEntry> log,
    List<Book> books,
  ) {
    final buckets = range.buckets;
    final bucketPages = List<int>.filled(buckets.length, 0);
    final perBook = <String, int>{};
    final days = <DateTime>{};
    var total = 0;
    for (final e in log) {
      if (!range.contains(e.day) || e.pages <= 0) continue;
      total += e.pages;
      days.add(e.day);
      perBook.update(e.bookId, (v) => v + e.pages, ifAbsent: () => e.pages);
      final i = buckets.indexWhere((b) => b.contains(e.day));
      if (i >= 0) bucketPages[i] += e.pages;
    }
    final byId = {for (final b in books) b.id: b};
    final byBook = [
      for (final MapEntry(:key, :value) in perBook.entries)
        if (byId[key] case final book?) (book: book, pages: value),
    ]..sort((a, b) => b.pages.compareTo(a.pages));
    final finished = [
      for (final b in books)
        if (b.status == ReadingStatus.read &&
            b.finishedAt != null &&
            range.contains(b.finishedAt!))
          b,
    ]..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!));
    return ReadingStats._(
      range: range,
      pages: total,
      bucketPages: bucketPages,
      finished: finished,
      byBook: byBook,
      activeDays: days.length,
    );
  }

  final StatsRange range;

  /// Total pages read in the range.
  final int pages;

  /// Pages per chart bucket, aligned with [StatsRange.buckets].
  final List<int> bucketPages;

  /// Books marked as read during the range, most recent first.
  final List<Book> finished;

  /// Pages per book, most-read first.
  final List<BookPages> byBook;

  /// Days with any reading.
  final int activeDays;

  /// Average pages per calendar day, counting only days up to [now].
  double averagePerDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day + 1);
    final end = today.isBefore(range.end) ? today : range.end;
    final days = end.isAfter(range.start)
        ? DateTime.utc(end.year, end.month, end.day)
              .difference(
                DateTime.utc(
                  range.start.year,
                  range.start.month,
                  range.start.day,
                ),
              )
              .inDays
        : 0;
    return days == 0 ? 0 : pages / days;
  }
}
