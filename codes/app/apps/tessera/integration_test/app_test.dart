// On-device end-to-end smoke for the Tessera app (the cutover port of the
// legacy browse→detail smoke onto the three-space IA).
//
// Runs the REAL app against the REAL local dev-stack (Hardhat node + the
// seeded "Demo Poll"), launched from `./dev-stack.sh e2e`. The emulator
// reaches the host stack via 10.0.2.2 (NATed to host loopback); endpoints are
// injected with --dart-define (see dev-stack.sh).
//
// Scope — the read path that proves the app ↔ chain wiring end to end:
// the VOTE space (the default route) loads, the DIRECTORY tab renders the
// seeded listed polls from a live `getListedPolls` read, and opening one
// resolves its module type on-chain into the voter journey screen.
//
// Run:  ./dev-stack.sh e2e
// or:   flutter test integration_test/app_test.dart -d emulator-5554 \
//         --dart-define RPC_URL=http://10.0.2.2:8545 \
//         --dart-define RELAYER_URL=http://10.0.2.2:3001 \
//         --dart-define REGISTRY_ADDRESS=<deployed registry>
import 'package:feature_vote/feature_vote.dart' show PollJourneyScreen;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tessera/main.dart' as app;

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
    'VOTE space -> directory -> poll screen, against the live seeded chain',
    (tester) async {
      // Boot the real app (production composition root: providers, router,
      // ChainReader at the injected RPC_URL).
      await app.main();
      await tester.pump(const Duration(seconds: 1));

      // --- The VOTE space is the default route; its home renders the
      //     MY VOTES / DIRECTORY tabs without any chain round-trip. ---
      expect(
        await pumpUntilFound(tester, find.text('DIRECTORY')),
        isTrue,
        reason: 'VOTE space home renders its tabs',
      );

      // --- DIRECTORY: a live getListedPolls read against the host chain.
      //     The seeded demo polls opt in to the public listing, so the
      //     "Demo Poll" card rendering proves the read reached the host
      //     node and decoded the registry. ---
      await tester.tap(find.text('DIRECTORY'));
      final demoPoll = find.text('Demo Poll');
      final loaded = await pumpUntilFound(
        tester,
        demoPoll,
        timeout: const Duration(seconds: 60),
      );
      if (!loaded) {
        final erroring = find
            .textContaining('Could not load the directory')
            .evaluate()
            .isNotEmpty;
        fail(
          'Seeded "Demo Poll" never rendered in the directory'
          '${erroring ? ' — the directory error view is showing, so the on-chain '
                    'read failed (host chain unreachable from the device?)' : ' (still loading?)'}.',
        );
      }

      // --- Open the poll -> /poll/:address. The poll screen resolves the
      //     module type from the chain and hosts the voter journey; the
      //     journey screen appearing proves the per-poll on-chain resolve. ---
      await tester.tap(demoPoll);
      await tester.pump(const Duration(seconds: 1));
      expect(
        await pumpUntilFound(tester, find.byType(PollJourneyScreen)),
        isTrue,
        reason: 'poll screen resolved the anon-vote module into the journey',
      );
      // The journey header shows the on-chain title + the jargon-free kind.
      expect(await pumpUntilFound(tester, find.text('Demo Poll')), isTrue);
      expect(find.text('PICK ONE'), findsWidgets);
    },
  );
}
