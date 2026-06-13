// Pull ContentWidth (and the theme) THROUGH the barrel re-export: theme.dart
// re-exports responsive.dart, so this single import also proves the helper is
// on the public design_system surface that consumers already use.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pump a ContentWidth into a window of [width] logical px and return the
  // laid-out width of the child's box.
  Future<double> childWidthAt(WidgetTester tester, double width) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkBauhausTheme(),
        home: Scaffold(
          body: ContentWidth(child: SizedBox.expand(key: key)),
        ),
      ),
    );
    return tester.getSize(find.byKey(key)).width;
  }

  testWidgets('fills the full width below the cap (phone-sized)', (
    tester,
  ) async {
    final w = await childWidthAt(tester, 400);
    expect(w, 400, reason: 'narrow screens stay full-bleed — no inset');
  });

  testWidgets('caps and centres on a wide window (desktop/web)', (
    tester,
  ) async {
    final w = await childWidthAt(tester, 1400);
    expect(
      w,
      ContentWidth.maxContentWidth,
      reason: 'content is capped at the single-column max on wide screens',
    );
    expect(
      w,
      lessThan(1400),
      reason: 'there must be horizontal empty space on either side',
    );
  });

  testWidgets('honours a custom maxWidth', (tester) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentWidth(maxWidth: 480, child: SizedBox.expand(key: key)),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)).width, 480);
  });
}
