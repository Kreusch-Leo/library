import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_reader/ui/reader/tap_zones.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late List<TapZone> taps;
  late int linkTaps;
  late TapGestureRecognizer link;

  setUp(() {
    taps = [];
    linkTaps = 0;
    link = TapGestureRecognizer()..onTap = () => linkTaps++;
  });
  tearDown(() => link.dispose());

  Future<void> pump(WidgetTester tester, {Widget? page}) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TapZones(
          onTap: (zone, _) => taps.add(zone),
          child: page ?? const ColoredBox(color: Colors.black),
        ),
      ),
    );
  }

  testWidgets('20 / 60 / 20 split maps to previous / menu / next', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(const Offset(100, 400)); // 10 %
    await tester.tapAt(const Offset(210, 400)); // 21 %: centre
    await tester.tapAt(const Offset(500, 400));
    await tester.tapAt(const Offset(790, 400)); // 79 %: centre
    await tester.tapAt(const Offset(900, 400));
    expect(taps, [
      TapZone.previous,
      TapZone.menu,
      TapZone.menu,
      TapZone.menu,
      TapZone.next,
    ]);
  });

  testWidgets('drags and long presses are not taps', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(
      tester,
      page: ListView(
        controller: scroll,
        children: [
          for (var i = 0; i < 50; i++)
            SizedBox(height: 100, child: Text('row $i')),
        ],
      ),
    );
    await tester.dragFrom(const Offset(900, 600), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.longPressAt(const Offset(100, 400));
    expect(taps, isEmpty);
    // The page underneath still received the drag.
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('taps on links go to the link, not the zone', (tester) async {
    await pump(
      tester,
      page: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 40),
            children: [
              const TextSpan(text: 'plain '),
              TextSpan(text: 'LINK', recognizer: link),
            ],
          ),
        ),
      ),
    );
    final linkBox = tester.getRect(find.text('plain LINK', findRichText: true));
    // Right part of the paragraph is the "LINK" span (still in the left zone).
    await tester.tapAt(Offset(linkBox.right - 10, linkBox.center.dy));
    expect(linkTaps, 1);
    expect(taps, isEmpty);

    // Left part ("plain") is ordinary text: the zone handles it.
    await tester.tapAt(Offset(linkBox.left + 10, linkBox.center.dy));
    expect(taps, [TapZone.previous]);
    expect(linkTaps, 1);
  });

  testWidgets('taps on click-cursor widgets (linked images) are left alone', (
    tester,
  ) async {
    var imageTaps = 0;
    await pump(
      tester,
      page: Align(
        alignment: Alignment.centerRight,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => imageTaps++,
            child: const SizedBox(
              width: 80,
              height: 80,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(960, 400));
    expect(imageTaps, 1);
    expect(taps, isEmpty);
  });
}
