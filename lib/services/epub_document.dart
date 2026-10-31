import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// An entry in the book's table of contents.
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.chapterIndex,
    this.depth = 0,
  });

  final String title;

  /// Index into [EpubDocument.chapters] (spine order).
  final int chapterIndex;
  final int depth;
}

/// One spine item (usually one XHTML file).
class EpubChapter {
  const EpubChapter({required this.href, required this.title});

  /// Path of the XHTML file inside the archive.
  final String href;
  final String title;
}

class EpubFormatException implements Exception {
  EpubFormatException(this.message);
  final String message;
  @override
  String toString() => 'EpubFormatException: $message';
}

/// A minimal, dependency-light EPUB 2/3 reader.
///
/// EPUB is a ZIP containing an OPF package file (metadata, manifest, spine)
/// plus XHTML content. This class parses just what the reader needs: title,
/// author, cover image, reading order and table of contents.
class EpubDocument {
  EpubDocument._({
    required Archive archive,
    required this.title,
    required this.author,
    required this.chapters,
    required this.toc,
    required this.coverHref,
  }) : _archive = archive; // ignore: prefer_initializing_formals

  final Archive _archive;
  final String title;
  final String author;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;

  /// Archive path of the cover image, if the book declares one.
  final String? coverHref;

  static Future<EpubDocument> openFile(String path) async =>
      parse(await File(path).readAsBytes());

  static EpubDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw EpubFormatException('Not a valid ZIP archive ($e)');
    }

    String? readText(String path) {
      final file = archive.findFile(path);
      if (file == null) return null;
      return _decodeUtf8(file.content);
    }

    // 1. container.xml points at the OPF package document.
    final container = readText('META-INF/container.xml');
    if (container == null) {
      throw EpubFormatException('Missing META-INF/container.xml');
    }
    final rootfile = XmlDocument.parse(container).descendantElements
        .firstWhere(
          (e) => e.localName == 'rootfile',
          orElse: () =>
              throw EpubFormatException('container.xml has no rootfile'),
        )
        .getAttribute('full-path');
    if (rootfile == null) throw EpubFormatException('rootfile has no path');

    final opfText = readText(rootfile);
    if (opfText == null) throw EpubFormatException('Missing $rootfile');
    final opf = XmlDocument.parse(opfText);
    final opfDir = p.posix.dirname(rootfile);

    String resolve(String href) => _resolveHref(opfDir, href);

    // 2. Metadata.
    final metadata = _child(opf.rootElement, 'metadata');
    final title = _firstText(metadata, 'title') ?? 'Untitled';
    final author = _firstText(metadata, 'creator') ?? 'Unknown author';

    // 3. Manifest: id -> (href, media-type, properties).
    final manifest = <String, _ManifestItem>{};
    final manifestEl = _child(opf.rootElement, 'manifest');
    for (final item in manifestEl?.childElements ?? <XmlElement>[]) {
      if (item.localName != 'item') continue;
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        href: resolve(href),
        mediaType: item.getAttribute('media-type') ?? '',
        properties: item.getAttribute('properties') ?? '',
      );
    }

    // 4. Spine (reading order).
    final spineEl = _child(opf.rootElement, 'spine');
    final spineHrefs = <String>[];
    for (final ref in spineEl?.childElements ?? <XmlElement>[]) {
      if (ref.localName != 'itemref') continue;
      if (ref.getAttribute('linear') == 'no') continue;
      final item = manifest[ref.getAttribute('idref')];
      if (item != null && archive.findFile(item.href) != null) {
        spineHrefs.add(item.href);
      }
    }
    if (spineHrefs.isEmpty) throw EpubFormatException('Empty spine');

    // 5. Table of contents: EPUB3 nav document, else EPUB2 NCX.
    var tocRaw = <_RawToc>[];
    final navItem = manifest.values
        .where((m) => m.properties.split(' ').contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final nav = readText(navItem.href);
      if (nav != null) tocRaw = _parseNav(nav, p.posix.dirname(navItem.href));
    }
    if (tocRaw.isEmpty) {
      final ncxId = spineEl?.getAttribute('toc');
      final ncxItem =
          manifest[ncxId] ??
          manifest.values
              .where((m) => m.mediaType == 'application/x-dtbncx+xml')
              .firstOrNull;
      if (ncxItem != null) {
        final ncx = readText(ncxItem.href);
        if (ncx != null) {
          tocRaw = _parseNcx(ncx, p.posix.dirname(ncxItem.href));
        }
      }
    }

    final toc = <EpubTocEntry>[];
    final chapterTitles = <int, String>{};
    for (final entry in tocRaw) {
      final index = spineHrefs.indexOf(entry.href);
      if (index < 0) continue;
      toc.add(
        EpubTocEntry(
          title: entry.title,
          chapterIndex: index,
          depth: entry.depth,
        ),
      );
      chapterTitles.putIfAbsent(index, () => entry.title);
    }

    // Chapters without their own TOC entry inherit the previous title.
    final chapters = <EpubChapter>[];
    var lastTitle = title;
    for (var i = 0; i < spineHrefs.length; i++) {
      lastTitle = chapterTitles[i] ?? lastTitle;
      chapters.add(EpubChapter(href: spineHrefs[i], title: lastTitle));
    }

    // 6. Cover image.
    String? coverHref = manifest.values
        .where((m) => m.properties.split(' ').contains('cover-image'))
        .firstOrNull
        ?.href;
    if (coverHref == null && metadata != null) {
      final coverId = metadata.childElements
          .where(
            (e) => e.localName == 'meta' && e.getAttribute('name') == 'cover',
          )
          .firstOrNull
          ?.getAttribute('content');
      coverHref = manifest[coverId]?.href;
    }
    coverHref ??= manifest.values
        .where(
          (m) =>
              m.mediaType.startsWith('image/') &&
              p.basename(m.href).toLowerCase().contains('cover'),
        )
        .firstOrNull
        ?.href;

    return EpubDocument._(
      archive: archive,
      title: title.trim(),
      author: author.trim(),
      chapters: chapters,
      toc: toc,
      coverHref: coverHref,
    );
  }

  Uint8List? readBytes(String href) {
    final file = _archive.findFile(href);
    return file?.content;
  }

  /// Uncompressed size of a chapter file; used to weight overall progress.
  int chapterSize(int index) =>
      max(1, _archive.findFile(chapters[index].href)?.size ?? 1);

  Uint8List? coverBytes() => coverHref == null ? null : readBytes(coverHref!);

  /// Raw XHTML of the chapter at [index].
  String chapterHtml(int index) {
    final bytes = readBytes(chapters[index].href);
    return bytes == null ? '' : _decodeUtf8(bytes);
  }

  /// Resolves [href] (as written inside chapter [index]) to an archive path.
  String resolveFromChapter(int index, String href) =>
      _resolveHref(p.posix.dirname(chapters[index].href), href);

  /// Spine index of the chapter at archive path [href] (fragment ignored).
  int chapterIndexForHref(String href) =>
      chapters.indexWhere((c) => c.href == href.split('#').first);

  /// Writes every non-document resource (images, fonts) to [dir] so the
  /// HTML renderer can load them via `file://` URIs. Idempotent.
  Future<void> extractResources(Directory dir) async {
    final marker = File(p.join(dir.path, '.extracted'));
    if (await marker.exists()) return;
    for (final file in _archive.files) {
      if (!file.isFile) continue;
      final lower = file.name.toLowerCase();
      if (lower.endsWith('.xhtml') ||
          lower.endsWith('.html') ||
          lower.endsWith('.htm') ||
          lower.endsWith('.opf') ||
          lower.endsWith('.ncx')) {
        continue;
      }
      final out = File(p.joinAll([dir.path, ...p.posix.split(file.name)]));
      // Guard against zip-slip: never write outside [dir].
      if (!p.isWithin(dir.path, out.path)) continue;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content);
    }
    await marker.writeAsString('ok');
  }

  // ---- helpers -------------------------------------------------------------

  static String _decodeUtf8(List<int> bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3; // strip BOM
    }
    return const Utf8Decoder(allowMalformed: true)
        .convert(bytes.sublist(start));
  }

  static String _resolveHref(String baseDir, String href) {
    final noFragment = Uri.decodeFull(href.split('#').first);
    final joined = baseDir == '.' || baseDir.isEmpty
        ? noFragment
        : p.posix.join(baseDir, noFragment);
    return p.posix.normalize(joined);
  }

  static XmlElement? _child(XmlElement parent, String localName) =>
      parent.childElements.where((e) => e.localName == localName).firstOrNull;

  static String? _firstText(XmlElement? parent, String localName) {
    final el = parent?.childElements
        .where((e) => e.localName == localName)
        .firstOrNull;
    final text = el?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static List<_RawToc> _parseNav(String xhtml, String baseDir) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xhtml);
    } catch (_) {
      return const [];
    }
    final navs = doc.descendantElements.where((e) => e.localName == 'nav');
    final tocNav =
        navs
            .where(
              (n) =>
                  (n.getAttribute('epub:type') ?? n.getAttribute('type') ?? '')
                      .contains('toc'),
            )
            .firstOrNull ??
        navs.firstOrNull;
    if (tocNav == null) return const [];
    final out = <_RawToc>[];
    void walk(XmlElement list, int depth) {
      for (final li in list.childElements.where((e) => e.localName == 'li')) {
        final anchor = li.childElements
            .where((e) => e.localName == 'a' || e.localName == 'span')
            .firstOrNull;
        final href = anchor?.getAttribute('href');
        final label = anchor?.innerText.trim().replaceAll(_ws, ' ') ?? '';
        if (href != null && label.isNotEmpty) {
          out.add(_RawToc(label, _resolveHref(baseDir, href), depth));
        }
        for (final sub in li.childElements.where((e) => e.localName == 'ol')) {
          walk(sub, depth + 1);
        }
      }
    }

    for (final ol in tocNav.childElements.where((e) => e.localName == 'ol')) {
      walk(ol, 0);
    }
    return out;
  }

  static List<_RawToc> _parseNcx(String ncx, String baseDir) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(ncx);
    } catch (_) {
      return const [];
    }
    final navMap = doc.descendantElements
        .where((e) => e.localName == 'navMap')
        .firstOrNull;
    if (navMap == null) return const [];
    final out = <_RawToc>[];
    void walk(XmlElement parent, int depth) {
      for (final point in parent.childElements.where(
        (e) => e.localName == 'navPoint',
      )) {
        final label = point.descendantElements
            .where((e) => e.localName == 'text')
            .firstOrNull
            ?.innerText
            .trim()
            .replaceAll(_ws, ' ');
        final src = point.childElements
            .where((e) => e.localName == 'content')
            .firstOrNull
            ?.getAttribute('src');
        if (label != null && label.isNotEmpty && src != null) {
          out.add(_RawToc(label, _resolveHref(baseDir, src), depth));
        }
        walk(point, depth + 1);
      }
    }

    walk(navMap, 0);
    return out;
  }

  static final _ws = RegExp(r'\s+');
}

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });
  final String href;
  final String mediaType;
  final String properties;
}

class _RawToc {
  const _RawToc(this.title, this.href, this.depth);
  final String title;
  final String href;
  final int depth;
}
