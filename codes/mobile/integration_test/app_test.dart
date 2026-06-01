// On-device end-to-end test for the zkVote mobile app.
//
// Runs the REAL app against the REAL local dev-stack (Hardhat node + the seeded
// "Demo Poll"), launched from `./dev-stack.sh e2e`. The emulator reaches the
// host stack via 10.0.2.2 (NATed to host loopback); endpoints are injected with
// --dart-define (see dev-stack.sh).
//
// Scope: the read paths that work on Android today — Browse (poll list from
// chain) -> Poll detail (real on-chain phase / participant count / options) ->
// Verify screen. Casting a vote needs client-side ZK proof generation, which is
// web-only on this build (the poll-detail screen says so), so it is out of
// scope here by design.
//
// Run:  ./dev-stack.sh e2e
// or:   flutter test integration_test/app_test.dart -d emulator-5554 \
//         --dart-define RPC_URL=http://10.0.2.2:8545 \
//         --dart-define RELAYER_URL=http://10.0.2.2:3001
import 'package:flutter/material.dart' show GestureDetector;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:zkvote_mobile/main.dart' as app;

/// Pump in a loop until [finder] matches or [timeout] elapses. Unlike
/// pumpAndSettle, this tolerates the indefinite loading-spinner animation while
/// an on-chain read is in flight (pumpAndSettle would time out on it).
Future<bool> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  Duration step = const Duration(milliseconds: 300),
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

  testWidgets(
    'browse -> poll detail -> verify, against the live seeded chain',
    (tester) async {
      // Boot the real app (loads ABIs from assets, wires ChainReader at the
      // injected RPC_URL, runApp).
      await app.main();
      await tester.pump(const Duration(seconds: 1));

      // --- Browse shows a loading state until the first on-chain read returns
      //     (over adb reverse on a device, or 10.0.2.2 on the emulator). Wait
      //     for the seeded poll to render: that proves the live read reached the
      //     host node, decoded PollCreated, and built the content (incl. the
      //     static 'POLLS' hero). ---
      final demoPoll = find.text('Demo Poll');
      final loaded = await pumpUntilFound(tester, demoPoll,
          timeout: const Duration(seconds: 60));
      if (!loaded) {
        final erroring =
            find.textContaining("COULDN'T LOAD").evaluate().isNotEmpty;
        fail('Seeded "Demo Poll" never rendered on Browse'
            '${erroring ? " — the error view is showing, so the on-chain read "
                "failed (host chain unreachable from the device?)" : " (still loading?)"}.');
      }
      expect(find.text('POLLS'), findsWidgets, reason: 'Browse hero + nav tab');

      // --- Open the poll -> /poll/:address (tap the card's InkWell) ---
      final card = find
          .ancestor(of: demoPoll, matching: find.byType(GestureDetector))
          .first;
      await tester.tap(card);
      await tester.pump(const Duration(seconds: 1));

      // Real per-poll on-chain read: the exact participant count (the seed
      // registers 2 voters) + the three options (Yes / No / Abstain).
      final registered = find.textContaining('2 REGISTERED');
      expect(
        await pumpUntilFound(tester, registered),
        isTrue,
        reason: 'poll detail shows the live "2 REGISTERED · 0 VOTES CAST"',
      );
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Abstain'), findsOneWidget);
      // Mobile is read-only for voting; in the Voting phase the vote area
      // renders that banner (the seed advances the poll to Voting).
      expect(find.textContaining('read-only'), findsWidgets,
          reason: 'mobile read-only voting banner (Voting phase)');

      // --- Back to Browse, then switch to the Verify tab via the nav bar ---
      await tester.tap(find.text('BACK TO POLLS'));
      await tester.pump(const Duration(seconds: 1));

      // The bottom NavigationBar destination labelled VERIFY (persistent chrome).
      expect(await pumpUntilFound(tester, find.text('VERIFY')), isTrue,
          reason: 'VERIFY nav tab present');
      await tester.tap(find.text('VERIFY').first);
      expect(
        await pumpUntilFound(tester, find.text('VERIFY RECEIPT')),
        isTrue,
        reason: 'Verify screen renders its receipt-check form',
      );
    },
  );
}
