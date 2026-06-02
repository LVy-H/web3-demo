// On-device test for the Identity feature against the REAL SecureIdentityStore
// (libsecret on Linux / Keychain / DPAPI). Boots the full app, navigates to the
// Identity tab, creates an identity, and confirms it persists — which proves the
// platform secure store is reachable at runtime on this target.
//
// Run:  flutter test integration_test/identity_test.dart -d linux
import 'package:flutter/material.dart' show NavigationDestination;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:zkvote_mobile/main.dart' as app;

Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Identity: navigate, create, persist (real secure store)',
      (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 1));

    // Jump to the Identity nav destination (bottom NavigationBar).
    final idTab = find.descendant(
      of: find.byType(NavigationDestination),
      matching: find.text('IDENTITY'),
    );
    expect(await pumpUntilFound(tester, find.text('IDENTITY')), isTrue);
    await tester.tap(idTab.first);
    await tester.pump(const Duration(seconds: 1));

    // The hero renders.
    expect(await pumpUntilFound(tester, find.text('IDENTITY')), isTrue,
        reason: 'Identity screen hero');

    // Start from a clean slate if a previous run left a seed.
    if (find.text('CLEAR IDENTITY').evaluate().isNotEmpty) {
      await tester.tap(find.text('CLEAR IDENTITY'));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(await pumpUntilFound(tester, find.text('CREATE NEW IDENTITY')), isTrue);

    // Create → must reach the ready state. If the secure store threw, the VM
    // would surface an error and stay on "No identity yet" instead.
    await tester.tap(find.text('CREATE NEW IDENTITY'));
    expect(
      await pumpUntilFound(tester, find.text('Identity ready')),
      isTrue,
      reason: 'creating an identity wrote to the real secure store and persisted',
    );
    expect(find.text('SEED'), findsOneWidget);

    // Reveal exposes a real 0x seed.
    await tester.tap(find.text('REVEAL'));
    expect(await pumpUntilFound(tester, find.textContaining('0x')), isTrue,
        reason: 'revealed seed is a 0x hex string');

    // Clean up so reruns start fresh.
    await tester.tap(find.text('CLEAR IDENTITY'));
    await tester.pump(const Duration(seconds: 1));
  });
}
