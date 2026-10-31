import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/data/models.dart';
import 'package:hearth_reader/services/reading_stats.dart';

Book _book(String id, {DateTime? finishedAt}) => Book(
  id: id,
  title: 'Book $id',
  author: 'A',
  format: BookFormat.pdf,
  filePath: '/$id.pdf',
  fileHash: id,
  addedAt: DateTime(2026),
  status: finishedAt == null ? ReadingStatus.reading : ReadingStatus.read,
  finishedAt: finishedAt,
);

ReadingLogEntry _log(DateTime day, String id, int pages) =>
    ReadingLogEntry(day: day, bookId: id, pages: pages);

void main() {
  // Wednesday 14 October 2026.
  final wed = DateTime(2026, 10, 14, 15, 30);

  group('StatsRange', () {
    test('periods contain the date and have the right bounds', () {
      StatsRange r(StatsPeriod p) => StatsRange.containing(p, wed);
      expect(
        (r(StatsPeriod.day).start, r(StatsPeriod.day).end),
        (DateTime(2026, 10, 14), DateTime(2026, 10, 15)),
      );
      expect(
        (r(StatsPeriod.week).start, r(StatsPeriod.week).end),
        (DateTime(2026, 10, 12), DateTime(2026, 10, 19)),
      ); // Mon–Sun
      expect(
        (r(StatsPeriod.month).start, r(StatsPeriod.month).end),
        (DateTime(2026, 10), DateTime(2026, 11)),
      );
      expect(
        (r(StatsPeriod.semester).start, r(StatsPeriod.semester).end),
        (DateTime(2026, 7), DateTime(2027)),
      );
      expect(
        (r(StatsPeriod.year).start, r(StatsPeriod.year).end),
        (DateTime(2026), DateTime(2027)),
      );
      expect(
        StatsRange.containing(
          StatsPeriod.semester,
          DateTime(2026, 6, 30),
        ).start,
        DateTime(2026),
      );
    });

    test('previous / next step across year boundaries', () {
      final jan = StatsRange.containing(
        StatsPeriod.month,
        DateTime(2026, 1, 5),
      );
      expect(jan.previous.start, DateTime(2025, 12));
      expect(jan.previous.next, jan);
      final h1 = StatsRange.containing(StatsPeriod.semester, DateTime(2026, 2));
      expect(h1.previous.start, DateTime(2025, 7));
      final week = StatsRange.containing(
        StatsPeriod.week,
        DateTime(2026, 1, 1),
      );
      expect(week.start, DateTime(2025, 12, 29));
      expect(week.next.start, DateTime(2026, 1, 5));
    });

    test('buckets: days for week/month, months for semester/year', () {
      expect(StatsRange.containing(StatsPeriod.day, wed).buckets, hasLength(1));
      expect(
        StatsRange.containing(StatsPeriod.week, wed).buckets,
        hasLength(7),
      );
      expect(
        StatsRange.containing(StatsPeriod.month, DateTime(2026, 2)).buckets,
        hasLength(28),
      );
      expect(
        StatsRange.containing(StatsPeriod.semester, wed).buckets,
        hasLength(6),
      );
      expect(
        StatsRange.containing(StatsPeriod.year, wed).buckets,
        hasLength(12),
      );
    });

    test('labels', () {
      expect(
        StatsRange.containing(StatsPeriod.day, wed).label,
        'Wed 14 Oct 2026',
      );
      expect(
        StatsRange.containing(StatsPeriod.week, wed).label,
        '12 – 18 Oct 2026',
      );
      expect(
        StatsRange.containing(StatsPeriod.week, DateTime(2026, 9, 30)).label,
        '28 Sep – 4 Oct 2026',
      );
      expect(
        StatsRange.containing(StatsPeriod.semester, wed).label,
        'Jul – Dec 2026',
      );
    });
  });

  group('ReadingStats.compute', () {
    final month = StatsRange.containing(StatsPeriod.month, wed);
    final books = [
      _book('a'),
      _book('b', finishedAt: DateTime(2026, 10, 3)),
      _book('c', finishedAt: DateTime(2026, 9, 30)), // previous month
    ];
    final log = [
      _log(DateTime(2026, 10, 1), 'a', 10),
      _log(DateTime(2026, 10, 1), 'b', 30),
      _log(DateTime(2026, 10, 14), 'a', 25),
      _log(DateTime(2026, 9, 30), 'c', 99), // outside the range
    ];

    test('totals, buckets, finished books and per-book breakdown', () {
      final s = ReadingStats.compute(month, log, books);
      expect(s.pages, 65);
      expect(s.bucketPages[0], 40);
      expect(s.bucketPages[13], 25);
      expect(s.bucketPages.reduce((a, b) => a + b), 65);
      expect(s.finished.map((b) => b.id), ['b']);
      expect(s.byBook.map((e) => (e.book.id, e.pages)), [('a', 35), ('b', 30)]);
      expect(s.activeDays, 2);
    });

    test('average per day only counts days up to today', () {
      final s = ReadingStats.compute(month, log, books);
      expect(s.averagePerDay(wed), closeTo(65 / 14, 1e-9));
      expect(s.averagePerDay(DateTime(2027)), closeTo(65 / 31, 1e-9));
      expect(s.averagePerDay(DateTime(2026, 9, 1)), 0);
    });

    test('semester buckets by month', () {
      final h2 = StatsRange.containing(StatsPeriod.semester, wed);
      final s = ReadingStats.compute(h2, log, books);
      expect(s.bucketPages, [0, 0, 99, 65, 0, 0]);
      expect(s.finished.map((b) => b.id), ['b', 'c']);
    });
  });
}
