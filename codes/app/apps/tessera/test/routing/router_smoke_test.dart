// Router smoke test (R2f): initial location, on-chain module resolution at
// /poll/:address, typed error states, and the canProve guard end-to-end
// through the real router + real composition.
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/app.dart';
import 'package:tessera/spaces/blocked_screen.dart';
import 'package:tessera/spaces/poll_screen.dart';
import 'package:tessera/spaces/route_error_screen.dart';
import 'package:tessera/spaces/vote_space_screen.dart';

import '../test_dependencies.dart';

const rankedAddr = '0x1111111111111111111111111111111111111111';
const unknownAddr = '0x3333333333333333333333333333333333333333';

void main() {
  testWidgets('initial location is /vote (the voter home)', (tester) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.byType(VoteSpaceScreen), findsOneWidget);
  });

  testWidgets(
    'deep link to /poll/:address renders the placeholder with the module '
    'resolved ON-CHAIN (no ?module= in the location)',
    (tester) async {
      final deps = await buildTestDependencies(
        fetchPolls: () async => [
          testPollInfo(rankedAddr, 'ranked-vote', title: 'Board ranking'),
        ],
      );
      await tester.pumpWidget(
        TesseraApp(dependencies: deps, initialLocation: '/poll/$rankedAddr'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PollScreen), findsOneWidget);
      expect(find.text('ranked-vote'), findsOneWidget);
      expect(find.text('Board ranking'), findsOneWidget);
    },
  );

  testWidgets('unknown poll address renders the typed not-found state', (
    tester,
  ) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(
      TesseraApp(dependencies: deps, initialLocation: '/poll/$unknownAddr'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PollScreen), findsOneWidget);
    expect(find.text('POLL NOT FOUND'), findsOneWidget);
  });

  testWidgets(
    'live-vote deep link is guard-redirected to /blocked on a device that '
    'cannot prove (test host has no prover)',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(
        TesseraApp(
          dependencies: deps,
          initialLocation: '/live/$rankedAddr/vote?t=w1',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        deps.appState.capabilities.canProve,
        isFalse,
        reason: 'precondition: the bare test host cannot prove',
      );
      expect(find.byType(BlockedScreen), findsOneWidget);
      expect(find.text('NOT ON THIS DEVICE'), findsOneWidget);
    },
  );

  testWidgets('unmatched location lands on the catch-all error route', (
    tester,
  ) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(
      TesseraApp(dependencies: deps, initialLocation: '/no/such/route'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RouteErrorScreen), findsOneWidget);
    expect(find.text('NOTHING HERE'), findsOneWidget);
  });
}
