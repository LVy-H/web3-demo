// R1 smoke test: the shell composes every workspace package and renders.
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/main.dart';

void main() {
  testWidgets('R1 shell renders with all core packages wired', (tester) async {
    await tester.pumpWidget(const TesseraApp());

    expect(find.text('TESSERA'), findsOneWidget);
    for (final pkg in [
      'core_domain',
      'core_chain',
      'core_crypto',
      'core_relay',
      'core_storage',
      'design_system',
    ]) {
      expect(find.text(pkg), findsOneWidget, reason: '$pkg row missing');
    }
  });
}
