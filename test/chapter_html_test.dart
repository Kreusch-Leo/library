import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/services/chapter_html.dart';

ChapterHtml _prep(String body, {String? resourceRoot}) => ChapterHtml.prepare(
  '<html><head><style>p{color:red}</style></head><body>$body</body></html>',
  chapterDir: 'OEBPS/text',
  resourceRoot: resourceRoot,
);

ChapterHighlight _hl(String text, {int occurrence = 0, String id = 'a1'}) =>
    ChapterHighlight(
      id: id,
      text: text,
      occurrence: occurrence,
      color: 0xFFE0A84E,
    );

void main() {
  group('ChapterHtml.prepare', () {
    test('strips scripts, styles and author colours', () {
      final html = _prep(
        '<script>alert(1)</script>'
        '<p style="color: #000; margin-left: 2em; background: white" '
        'bgcolor="#fff">Hello</p>',
      ).render(const []);
      expect(html, isNot(contains('script')));
      expect(html, isNot(contains('color')));
      expect(html, isNot(contains('background')));
      expect(html, contains('margin-left: 2em'));
    });

    test('rewrites images to file URIs and links to epub: targets', () {
      final html = _prep(
        '<img src="../images/a%20b.png" width="900"/>'
        '<a href="ch2.xhtml#note">next</a>'
        '<a href="#local">here</a>'
        '<a href="https://example.com">web</a>',
        resourceRoot: '/data/cache',
      ).render(const []);
      expect(html, contains('src="file:///data/cache/OEBPS/images/a%20b.png"'));
      expect(html, isNot(contains('width')));
      expect(html, contains('href="epub:OEBPS/text/ch2.xhtml#note"'));
      expect(html, contains('href="epub:#local"'));
      expect(html, contains('href="https://example.com"'));
    });

    test('drops images when no resource root is available', () {
      final html = _prep('<p>x<img src="a.png"/></p>').render(const []);
      expect(html, isNot(contains('<img')));
    });

    test('turns SVG-wrapped cover images into <img>', () {
      final html = _prep(
        '<svg><image xlink:href="../images/cover.jpg"/></svg>',
        resourceRoot: '/r',
      ).render(const []);
      expect(html, contains('<img src="file:///r/OEBPS/images/cover.jpg"'));
      expect(html, isNot(contains('<svg')));
    });
  });

  group('highlights', () {
    test('wraps a passage that spans several text nodes', () {
      final html = _prep('<p>The lamp was lit at <b>dusk</b>, as always.</p>')
          .render([_hl('lit at dusk, as')]);
      expect(html, contains('<a href="hl:a1" data-hl="ffe0a84e">lit at </a>'));
      expect(
        html,
        contains('<b><a href="hl:a1" data-hl="ffe0a84e">dusk</a></b>'),
      );
      expect(
        html,
        contains('<a href="hl:a1" data-hl="ffe0a84e">, as</a> always.'),
      );
    });

    test('matches across block boundaries regardless of whitespace', () {
      // The rendered selection has a newline between paragraphs; the DOM
      // has none.
      final html = _prep('<p>end of one.</p><p>Start of two</p>')
          .render([_hl('one.\nStart')]);
      expect(html, contains('>one.</a></p>'));
      expect(html, contains('<p><a href="hl:a1" data-hl="ffe0a84e">Start</a>'));
    });

    test('picks the requested occurrence', () {
      final html = _prep('<p>echo one echo two echo</p>')
          .render([_hl('echo', occurrence: 1)]);
      expect(
        html,
        'echo one <a href="hl:a1" data-hl="ffe0a84e">echo</a> two echo'.let(
          (s) => '<p>$s</p>',
        ),
      );
    });

    test('uses <mark> inside existing links to avoid nested anchors', () {
      final html = _prep('<p><a href="https://x.y">a link here</a></p>')
          .render([_hl('link')]);
      expect(html, contains('<mark data-hl="ffe0a84e">link</mark>'));
      expect(html, isNot(contains('hl:a1')));
    });

    test('ignores highlights whose text is gone', () {
      final html = _prep('<p>abc</p>').render([_hl('zzz')]);
      expect(html, '<p>abc</p>');
    });

    test('render does not mutate the prepared chapter', () {
      final chapter = _prep('<p>abc def</p>');
      chapter.render([_hl('abc')]);
      expect(chapter.render(const []), '<p>abc def</p>');
    });

    test('occurrenceNear chooses the match closest to the selection', () {
      final chapter = _prep('<p>cat sat. cat ran. cat hid.</p>');
      expect(chapter.occurrenceNear('cat', 0), 0);
      expect(chapter.occurrenceNear('cat', 9), 1);
      expect(chapter.occurrenceNear('cat', 30), 2);
      expect(chapter.occurrenceNear('dog', 0), isNull);
    });

    test('fractionOf locates a passage within the chapter', () {
      final chapter = _prep('<p>${'word ' * 50}needle ${'word ' * 49}</p>');
      expect(chapter.fractionOf('needle', 0), closeTo(0.5, 0.02));
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
