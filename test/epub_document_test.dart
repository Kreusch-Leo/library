import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/services/epub_document.dart';
import 'package:path/path.dart' as p;

import 'support/fake_epub.dart';

void main() {
  group('EpubDocument', () {
    test('parses EPUB 3 metadata, spine, nav TOC and cover', () {
      final doc = EpubDocument.parse(buildEpub());
      expect(doc.title, 'The Lantern Keeper');
      expect(doc.author, 'Ada Moss');
      expect(doc.chapters.map((c) => c.href), [
        'OEBPS/text/ch0.xhtml',
        'OEBPS/text/ch1.xhtml',
      ]);
      expect(doc.toc.map((e) => e.title), ['Chapter 1', 'Chapter 2']);
      expect(doc.chapters[1].title, 'Chapter 2');
      expect(doc.coverHref, 'OEBPS/images/cover.jpg');
      expect(doc.coverBytes(), [1, 2, 3]);
      expect(doc.chapterHtml(0), contains('The lamp was lit'));
      expect(doc.chapterSize(0), greaterThan(1));
    });

    test('falls back to EPUB 2 NCX and <meta name="cover">', () {
      final doc = EpubDocument.parse(buildEpub(epub3: false));
      expect(doc.toc.map((e) => e.title), ['Part 1', 'Part 2']);
      expect(doc.coverHref, 'OEBPS/images/cover.jpg');
    });

    test('resolves relative hrefs from a chapter', () {
      final doc = EpubDocument.parse(buildEpub());
      expect(
        doc.resolveFromChapter(1, '../images/gull.png'),
        'OEBPS/images/gull.png',
      );
      expect(doc.chapterIndexForHref('OEBPS/text/ch1.xhtml#part'), 1);
    });

    test('rejects non-EPUB data', () {
      expect(
        () => EpubDocument.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<EpubFormatException>()),
      );
    });

    test('extracts resources without chapters, idempotently', () async {
      final tmp = await Directory.systemTemp.createTemp('hearth_epub');
      addTearDown(() => tmp.delete(recursive: true));
      final doc = EpubDocument.parse(buildEpub());
      await doc.extractResources(tmp);
      expect(
        File(p.join(tmp.path, 'OEBPS', 'images', 'gull.png')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(tmp.path, 'OEBPS', 'text', 'ch0.xhtml')).existsSync(),
        isFalse,
      );
      await doc.extractResources(tmp); // second call is a no-op
    });
  });
}
