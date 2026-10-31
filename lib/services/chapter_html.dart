import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

/// A highlight to paint into a chapter.
class ChapterHighlight {
  const ChapterHighlight({
    required this.id,
    required this.text,
    required this.occurrence,
    required this.color,
  });

  final String id;
  final String text;
  final int occurrence;
  final int color;
}

/// URL scheme used for highlight anchors (`hl:<annotation id>`).
const highlightScheme = 'hl:';

/// URL scheme used for links between chapters (`epub:<archive path>#frag`).
const epubLinkScheme = 'epub:';

/// Turns raw chapter XHTML into HTML suitable for a strictly dark reader and
/// maps highlights onto it.
class ChapterHtml {
  ChapterHtml._(this._body);

  final dom.Element _body;

  /// Parses and sanitises a chapter.
  ///
  /// * [chapterDir] — directory of the chapter inside the archive, used to
  ///   resolve relative image and link targets.
  /// * [resourceRoot] — local directory where archive resources were
  ///   extracted; images are rewritten to `file://` URIs below it.
  factory ChapterHtml.prepare(
    String rawHtml, {
    required String chapterDir,
    String? resourceRoot,
  }) {
    final doc = html_parser.parse(rawHtml);
    final body = doc.body ?? dom.Element.tag('body');

    for (final el in body.querySelectorAll(
      'script, style, link, iframe, object, embed, form, input, button',
    )) {
      el.remove();
    }

    String resolve(String href) {
      final clean = Uri.decodeFull(href.split('#').first);
      final joined = (chapterDir == '.' || chapterDir.isEmpty)
          ? clean
          : p.posix.join(chapterDir, clean);
      return p.posix.normalize(joined);
    }

    String? fileUri(String archivePath) => resourceRoot == null
        ? null
        : Uri.file(p.joinAll([resourceRoot, ...p.posix.split(archivePath)]))
              .toString();

    // SVG wrappers around a single <image> (common for cover pages) become
    // plain <img> elements, since the renderer does not draw SVG.
    for (final svg in body.querySelectorAll('svg')) {
      final image = svg.getElementsByTagName('image').firstOrNull;
      // `xlink:href` is parsed as a namespaced attribute, so its key is not
      // a plain string; match on the local name instead.
      final href = image?.attributes.entries
          .where((e) => '${e.key}' == 'href' || '${e.key}'.endsWith(':href'))
          .firstOrNull
          ?.value;
      if (href != null) {
        svg.replaceWith(dom.Element.tag('img')..attributes['src'] = href);
      } else {
        svg.remove();
      }
    }

    for (final img in body.querySelectorAll('img')) {
      final src = img.attributes['src'];
      if (src == null || src.startsWith('data:')) continue;
      final uri = fileUri(resolve(src));
      if (uri == null) {
        img.remove();
      } else {
        img.attributes['src'] = uri;
      }
      img.attributes.remove('width');
      img.attributes.remove('height');
    }

    for (final a in body.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      if (href.startsWith('http://') ||
          href.startsWith('https://') ||
          href.startsWith('mailto:')) {
        continue;
      }
      if (href.startsWith('#')) {
        a.attributes['href'] = '$epubLinkScheme#${href.substring(1)}';
      } else {
        final frag = href.contains('#') ? '#${href.split('#').last}' : '';
        a.attributes['href'] = '$epubLinkScheme${resolve(href)}$frag';
      }
    }

    // Strip author colours so the dark theme always wins.
    for (final el in body.querySelectorAll('*')) {
      el.attributes.remove('bgcolor');
      el.attributes.remove('color');
      el.attributes.remove('background');
      final style = el.attributes['style'];
      if (style != null) {
        final kept = style
            .split(';')
            .where((decl) {
              final prop = decl.split(':').first.trim().toLowerCase();
              return prop.isNotEmpty &&
                  !prop.startsWith('color') &&
                  !prop.startsWith('background') &&
                  !prop.startsWith('font-family') &&
                  prop != 'font-size' &&
                  prop != 'line-height';
            })
            .join(';');
        if (kept.isEmpty) {
          el.attributes.remove('style');
        } else {
          el.attributes['style'] = kept;
        }
      }
    }

    return ChapterHtml._(body);
  }

  /// Returns the HTML with [highlights] wrapped in tappable anchors.
  String render(List<ChapterHighlight> highlights) {
    final body = _body.clone(true);
    if (highlights.isNotEmpty) _applyHighlights(body, highlights);
    return body.innerHtml;
  }

  /// Chooses which occurrence of [selectedText] the user selected.
  ///
  /// [approxRenderedOffset] is the selection start offset reported by the
  /// selection system (relative to the rendered chapter text). Returns the
  /// index of the matching occurrence closest to it, or `null` when the text
  /// cannot be found at all.
  int? occurrenceNear(String selectedText, int? approxRenderedOffset) {
    final index = _TextIndex.build(_body);
    final matches = index.findAll(selectedText);
    if (matches.isEmpty) return null;
    if (approxRenderedOffset == null || matches.length == 1) return 0;
    var best = 0;
    var bestDistance = 1 << 62;
    for (var i = 0; i < matches.length; i++) {
      final collapsed = index.collapsedPos[matches[i]];
      final distance = (collapsed - approxRenderedOffset).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Approximate position (0..1) of a passage within the chapter, used to
  /// scroll to a highlight.
  double? fractionOf(String text, int occurrence) {
    final index = _TextIndex.build(_body);
    final matches = index.findAll(text);
    if (matches.isEmpty || index.collapsedLength == 0) return null;
    final at = matches[occurrence.clamp(0, matches.length - 1)];
    return index.collapsedPos[at] / index.collapsedLength;
  }

  static void _applyHighlights(
    dom.Element body,
    List<ChapterHighlight> highlights,
  ) {
    final index = _TextIndex.build(body);

    // Gather per-text-node ranges first; mutate afterwards.
    final ranges = <int, List<_NodeRange>>{};
    for (final hl in highlights) {
      final matches = index.findAll(hl.text);
      if (matches.isEmpty) continue;
      final start = matches[hl.occurrence.clamp(0, matches.length - 1)];
      final end = start + _TextIndex.strip(hl.text).length - 1;
      final (startNode, startOff) = index.charMap[start];
      final (endNode, endOff) = index.charMap[end];
      for (var n = startNode; n <= endNode; n++) {
        final nodeLen = index.nodes[n].text.length;
        final from = n == startNode ? startOff : 0;
        final to = n == endNode ? endOff + 1 : nodeLen;
        if (to > from) {
          ranges.putIfAbsent(n, () => []).add(_NodeRange(from, to, hl));
        }
      }
    }

    ranges.forEach((nodeIndex, list) {
      final node = index.nodes[nodeIndex];
      final parent = node.parentNode;
      if (parent == null) return;
      list.sort((a, b) => a.from.compareTo(b.from));
      final text = node.text;
      final insideLink = _hasAncestor(node, 'a');
      final pieces = <dom.Node>[];
      var cursor = 0;
      for (final r in list) {
        final from = r.from < cursor ? cursor : r.from; // trim overlaps
        if (from >= r.to) continue;
        if (from > cursor) pieces.add(dom.Text(text.substring(cursor, from)));
        final wrapper = insideLink
            ? dom.Element.tag('mark')
            : (dom.Element.tag('a')
                ..attributes['href'] = '$highlightScheme${r.hl.id}');
        wrapper.attributes['data-hl'] = r.hl.color.toRadixString(16);
        wrapper.append(dom.Text(text.substring(from, r.to)));
        pieces.add(wrapper);
        cursor = r.to;
      }
      if (cursor < text.length) pieces.add(dom.Text(text.substring(cursor)));
      for (final piece in pieces) {
        parent.insertBefore(piece, node);
      }
      node.remove();
    });
  }

  static bool _hasAncestor(dom.Node node, String tag) {
    var current = node.parent;
    while (current != null) {
      if (current.localName == tag) return true;
      current = current.parent;
    }
    return false;
  }
}

class _NodeRange {
  _NodeRange(this.from, this.to, this.hl);
  final int from;
  final int to;
  final ChapterHighlight hl;
}

/// Whitespace-insensitive index of a DOM subtree's text.
///
/// Rendered text and DOM text differ in whitespace (collapsing, block
/// breaks), so matching is done on the sequence of non-whitespace
/// characters, with a map back to (text node, offset).
class _TextIndex {
  _TextIndex._();

  final nodes = <dom.Text>[];
  final buffer = StringBuffer();

  /// For each stripped char: (node index, offset in node).
  final charMap = <(int, int)>[];

  /// For each stripped char: its approximate offset in rendered text.
  final collapsedPos = <int>[];
  int collapsedLength = 0;

  late final String stripped = buffer.toString();

  static bool _isIgnorable(int c) =>
      c == 0x20 ||
      (c >= 0x09 && c <= 0x0D) ||
      c == 0xA0 ||
      c == 0xAD ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200D) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000 ||
      c == 0xFEFF;

  /// Removes whitespace and invisible formatting characters.
  static String strip(String s) {
    final out = StringBuffer();
    for (final c in s.codeUnits) {
      if (!_isIgnorable(c)) out.writeCharCode(c);
    }
    return out.toString();
  }

  static const _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'section',
    'article',
    'br',
    'tr',
    'pre',
    'figure',
    'figcaption',
    'hr',
  };

  static _TextIndex build(dom.Element root) {
    final index = _TextIndex._();
    var lastWasSpace = true;
    void visit(dom.Node node) {
      if (node is dom.Text) {
        final nodeIndex = index.nodes.length;
        index.nodes.add(node);
        final text = node.text;
        for (var i = 0; i < text.length; i++) {
          final c = text.codeUnitAt(i);
          if (_isIgnorable(c)) {
            if (!lastWasSpace && c != 0xAD) {
              index.collapsedLength++;
              lastWasSpace = true;
            }
            continue;
          }
          index.buffer.writeCharCode(c);
          index.charMap.add((nodeIndex, i));
          index.collapsedPos.add(index.collapsedLength);
          index.collapsedLength++;
          lastWasSpace = false;
        }
      } else if (node is dom.Element) {
        final isBlock = _blockTags.contains(node.localName);
        if (isBlock && !lastWasSpace) {
          index.collapsedLength++;
          lastWasSpace = true;
        }
        for (final child in node.nodes.toList()) {
          visit(child);
        }
        if (isBlock && !lastWasSpace) {
          index.collapsedLength++;
          lastWasSpace = true;
        }
      }
    }

    visit(root);
    return index;
  }

  /// Start indices (into [stripped]) of every match of [needle].
  List<int> findAll(String needle) {
    final n = strip(needle);
    if (n.isEmpty) return const [];
    final out = <int>[];
    var from = 0;
    while (true) {
      final at = stripped.indexOf(n, from);
      if (at < 0) break;
      out.add(at);
      from = at + 1;
    }
    return out;
  }
}
