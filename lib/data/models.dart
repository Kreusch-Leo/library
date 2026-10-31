import 'dart:convert';

enum BookFormat {
  pdf,
  epub;

  static BookFormat fromName(String name) =>
      BookFormat.values.firstWhere((f) => f.name == name);

  static BookFormat? fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return BookFormat.pdf;
    if (lower.endsWith('.epub')) return BookFormat.epub;
    return null;
  }
}

enum ReadingStatus {
  tbr('TBR'),
  reading('Reading'),
  read('Read');

  const ReadingStatus(this.label);
  final String label;

  static ReadingStatus fromName(String name) =>
      ReadingStatus.values.firstWhere((s) => s.name == name);
}

/// Where the reader currently is inside a book.
///
/// PDFs use [page] (1-based). EPUBs use [chapter] (spine index) plus
/// [offset], the scroll fraction (0..1) inside that chapter.
class ReadingPosition {
  const ReadingPosition.pdf(int this.page) : chapter = null, offset = null;
  const ReadingPosition.epub(int this.chapter, double this.offset)
    : page = null;

  final int? page;
  final int? chapter;
  final double? offset;

  Map<String, Object?> toJson() => {
    if (page != null) 'page': page,
    if (chapter != null) 'chapter': chapter,
    if (offset != null) 'offset': offset,
  };

  String encode() => jsonEncode(toJson());

  static ReadingPosition? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['page'] != null) return ReadingPosition.pdf(map['page'] as int);
    if (map['chapter'] != null) {
      return ReadingPosition.epub(
        map['chapter'] as int,
        (map['offset'] as num?)?.toDouble() ?? 0,
      );
    }
    return null;
  }
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.filePath,
    required this.fileHash,
    required this.addedAt,
    this.coverPath,
    this.status = ReadingStatus.tbr,
    this.lastOpenedAt,
    this.progress = 0,
    this.position,
    this.currentPage = 0,
    this.totalPages = 0,
  });

  final String id;
  final String title;
  final String author;
  final BookFormat format;
  final String filePath;
  final String fileHash;
  final String? coverPath;
  final ReadingStatus status;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  /// Overall progress through the book, 0..1.
  final double progress;
  final ReadingPosition? position;

  /// Last page reached (1-based) and page count, for paginated formats.
  /// Both are 0 when unknown (never opened, or a reflowable EPUB).
  final int currentPage;
  final int totalPages;

  /// Reading completion, 0..1. Uses page counts when known and falls back
  /// to [progress] (e.g. for EPUBs, which have no fixed pages).
  double get completion => totalPages > 0
      ? (currentPage / totalPages).clamp(0.0, 1.0)
      : progress.clamp(0.0, 1.0);

  /// Completion as a whole percentage, e.g. 45.
  int get completionPercent => (completion * 100).round();

  Book copyWith({
    String? title,
    String? author,
    String? coverPath,
    ReadingStatus? status,
    DateTime? lastOpenedAt,
    double? progress,
    ReadingPosition? position,
    int? currentPage,
    int? totalPages,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    format: format,
    filePath: filePath,
    fileHash: fileHash,
    coverPath: coverPath ?? this.coverPath,
    status: status ?? this.status,
    addedAt: addedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    progress: progress ?? this.progress,
    position: position ?? this.position,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format.name,
    'file_path': filePath,
    'file_hash': fileHash,
    'cover_path': coverPath,
    'status': status.name,
    'added_at': addedAt.millisecondsSinceEpoch,
    'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
    'progress': progress,
    'position': position?.encode(),
    'current_page': currentPage,
    'total_pages': totalPages,
  };

  static Book fromRow(Map<String, Object?> row) => Book(
    id: row['id']! as String,
    title: row['title']! as String,
    author: row['author']! as String,
    format: BookFormat.fromName(row['format']! as String),
    filePath: row['file_path']! as String,
    fileHash: row['file_hash']! as String,
    coverPath: row['cover_path'] as String?,
    status: ReadingStatus.fromName(row['status']! as String),
    addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at']! as int),
    lastOpenedAt: row['last_opened_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['last_opened_at']! as int),
    progress: (row['progress'] as num?)?.toDouble() ?? 0,
    position: ReadingPosition.decode(row['position'] as String?),
    currentPage: row['current_page'] as int? ?? 0,
    totalPages: row['total_pages'] as int? ?? 0,
  );
}

/// A rectangle in PDF page coordinates (points, origin bottom-left, so
/// [top] > [bottom]), independent of zoom and screen size.
class PageRect {
  const PageRect(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;

  List<double> toJson() => [left, top, right, bottom];
  static PageRect fromJson(List<dynamic> v) => PageRect(
    (v[0] as num).toDouble(),
    (v[1] as num).toDouble(),
    (v[2] as num).toDouble(),
    (v[3] as num).toDouble(),
  );
}

/// Locates a highlighted passage inside a book.
///
/// * PDF: [page] (1-based) and the highlight [rects] on that page.
/// * EPUB: [chapter] (spine index) and [occurrence], the index of this
///   passage among identical text matches within the chapter.
class AnnotationLocator {
  const AnnotationLocator.pdf({required int this.page, this.rects = const []})
    : chapter = null,
      occurrence = 0;
  const AnnotationLocator.epub({required int this.chapter, this.occurrence = 0})
    : page = null,
      rects = const [];

  final int? page;
  final List<PageRect> rects;
  final int? chapter;
  final int occurrence;

  String encode() => jsonEncode({
    if (page != null) 'page': page,
    if (rects.isNotEmpty) 'rects': [for (final r in rects) r.toJson()],
    if (chapter != null) 'chapter': chapter,
    'occurrence': occurrence,
  });

  static AnnotationLocator decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['page'] != null) {
      return AnnotationLocator.pdf(
        page: map['page'] as int,
        rects: [
          for (final r in (map['rects'] as List<dynamic>? ?? const []))
            PageRect.fromJson(r as List<dynamic>),
        ],
      );
    }
    return AnnotationLocator.epub(
      chapter: map['chapter'] as int,
      occurrence: map['occurrence'] as int? ?? 0,
    );
  }
}

class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.selectedText,
    required this.locator,
    required this.createdAt,
    required this.updatedAt,
    this.note = '',
    this.color = defaultColor,
    this.sectionLabel,
  });

  static const int defaultColor = 0xFFE0A84E;

  /// Highlight colours offered in the UI (amber, sage, rose, sky).
  static const List<int> palette = [
    0xFFE0A84E,
    0xFF8DB58A,
    0xFFD98C8C,
    0xFF7FA7C9,
  ];

  final String id;
  final String bookId;
  final String selectedText;

  /// Markdown note attached to the passage. Empty means "highlight only".
  final String note;
  final int color;
  final AnnotationLocator locator;

  /// Human readable location, e.g. "Page 12" or "Chapter 3".
  final String? sectionLabel;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasNote => note.trim().isNotEmpty;

  Annotation copyWith({String? note, int? color}) => Annotation(
    id: id,
    bookId: bookId,
    selectedText: selectedText,
    locator: locator,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    note: note ?? this.note,
    color: color ?? this.color,
    sectionLabel: sectionLabel,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'book_id': bookId,
    'selected_text': selectedText,
    'note': note,
    'color': color,
    'locator': locator.encode(),
    'section_label': sectionLabel,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  static Annotation fromRow(Map<String, Object?> row) => Annotation(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    selectedText: row['selected_text']! as String,
    note: row['note'] as String? ?? '',
    color: row['color'] as int? ?? defaultColor,
    locator: AnnotationLocator.decode(row['locator']! as String),
    sectionLabel: row['section_label'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
