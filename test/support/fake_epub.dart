import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a small but structurally realistic EPUB in memory.
Uint8List buildEpub({
  String title = 'The Lantern Keeper',
  String author = 'Ada Moss',
  bool epub3 = true,
  List<String>? chapters,
  bool withCover = true,
}) {
  final bodies =
      chapters ??
      [
        '<h1>One</h1><p>The lamp was lit at <b>dusk</b>, as always.</p>'
            '<p>She climbed the stairs.</p>',
        '<h1>Two</h1><p>Morning came slowly over the harbour.</p>'
            '<img src="../images/gull.png" alt="gull"/>',
      ];
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < bodies.length; i++) {
    manifest.writeln(
      '<item id="c$i" href="text/ch$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.writeln('<itemref idref="c$i"/>');
    add('OEBPS/text/ch$i.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c$i</title>
<style>p { color: black; }</style></head>
<body>${bodies[i]}</body></html>''');
  }
  if (withCover) {
    manifest.writeln(
      epub3
          ? '<item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>'
          : '<item id="cover" href="images/cover.jpg" media-type="image/jpeg"/>',
    );
    archive.addFile(ArchiveFile('OEBPS/images/cover.jpg', 3, [1, 2, 3]));
  }
  archive.addFile(ArchiveFile('OEBPS/images/gull.png', 4, [9, 9, 9, 9]));

  if (epub3) {
    manifest.writeln(
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    );
    add('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol>
${[for (var i = 0; i < bodies.length; i++) '<li><a href="text/ch$i.xhtml">Chapter ${i + 1}</a></li>'].join('\n')}
</ol></nav></body></html>''');
  } else {
    manifest.writeln(
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    );
    add('OEBPS/toc.ncx', '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>
${[for (var i = 0; i < bodies.length; i++) '<navPoint id="n$i"><navLabel><text>Part ${i + 1}</text></navLabel><content src="text/ch$i.xhtml"/></navPoint>'].join('\n')}
</navMap></ncx>''');
  }

  add('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="${epub3 ? '3.0' : '2.0'}">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    ${!epub3 && withCover ? '<meta name="cover" content="cover"/>' : ''}
  </metadata>
  <manifest>
$manifest  </manifest>
  <spine${epub3 ? '' : ' toc="ncx"'}>
$spine  </spine>
</package>''');

  return Uint8List.fromList(ZipEncoder().encode(archive));
}
