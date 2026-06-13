// Responsive content-width guard for the three-space shell.
//
// On web/desktop the single-column body must read well on a wide window:
// the content column is capped + centred (no edge-to-edge line lengths),
// WHILE the dot-grid page texture stays FULL-BLEED behind it (the shell
// extends the body behind the notched bar, and the meniscus shows the grid).
// Phones stay full-width. These tests lock in both halves so a future
// "just wrap the body" change can't silently shrink the background.
import 'package:design_system/dot_grid_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/app.dart';

import '../test_dependencies.dart';

void main() {
  Future<void> pumpShellAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();
  }

  double dotGridWidth(WidgetTester tester) {
    final box =
        find.byType(DotGridBackground).evaluate().first.findRenderObject()
            as RenderBox;
    return box.size.width;
  }

  // Left inset of the VOTE space heading == empty space to the left of the
  // capped content column. Zero on phones, sizable when centred on desktop.
  double contentLeftInset(WidgetTester tester) {
    final box =
        find.text('VOTE').evaluate().first.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero).dx;
  }

  testWidgets('phone width: content is full-bleed (no centring inset) and the '
      'dot-grid fills the screen', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const phone = Size(400, 900);
    await pumpShellAt(tester, phone);

    expect(dotGridWidth(tester), phone.width, reason: 'dot-grid is full-bleed');
    // The heading sits behind a 24px content padding only — no centring gap.
    expect(
      contentLeftInset(tester),
      lessThan(40),
      reason: 'no extra horizontal inset on a phone (content fills width)',
    );
  });

  testWidgets('desktop width: content is capped + centred while the dot-grid '
      'stays full-bleed', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const wide = Size(1400, 1000);
    await pumpShellAt(tester, wide);

    // The page texture must NOT be capped — it spans the whole window so the
    // notch meniscus and the area behind the bar keep showing the grid.
    expect(
      dotGridWidth(tester),
      wide.width,
      reason: 'dot-grid must stay full-bleed on wide screens',
    );

    // The content column, by contrast, is centred: there is real horizontal
    // empty space to its left (and by symmetry, its right).
    expect(
      contentLeftInset(tester),
      greaterThan(200),
      reason: 'content is centred with horizontal empty space on a wide window',
    );
  });
}
