import 'package:design_system/theme.dart';
import 'package:design_system/widgets/tessera_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildDarkBauhausTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders at the requested size with a Tessera semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(host(const TesseraMark(size: 96)));

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(TesseraMark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.size, const Size.square(96));
    expect(find.bySemanticsLabel('Tessera'), findsOneWidget);
  });

  testWidgets('paints at favicon and icon scales without errors', (
    tester,
  ) async {
    // The mark must stay valid at 16px (favicon) and 512px (store icon);
    // the painter scales one 512-space geometry, so both must lay out and
    // paint cleanly.
    await tester.pumpWidget(
      host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TesseraMark(size: 16),
            TesseraMark(size: 512, background: true),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TesseraMark), findsNWidgets(2));
  });
}
