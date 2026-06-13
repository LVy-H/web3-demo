// About screen (R3 polish): renders app/backend info and — per spec §3
// principle 5 — leaks no crypto jargon into voter-facing copy.
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: AboutScreen(version: '0.3.0+1')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the about surface with the version row', (tester) async {
    await pump(tester);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('0.3.0+1'), findsOneWidget);
  });

  testWidgets('no crypto jargon leaks into the voter-facing copy', (
    tester,
  ) async {
    await pump(tester);

    // Sweep every rendered Text on the screen — the privacy row used to read
    // "zero-knowledge proofs (Semaphore v4)", which is exactly the banned
    // vocabulary the product rule forbids in user copy.
    for (final banned in [
      'Semaphore',
      'zero-knowledge',
      'commitment',
      'nullifier',
    ]) {
      expect(
        find.textContaining(banned, findRichText: true),
        findsNothing,
        reason: '"$banned" is crypto jargon (spec §3 principle 5)',
      );
    }
  });
}
