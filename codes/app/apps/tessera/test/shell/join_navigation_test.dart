// Regression for the duplicate-page-key crash (Navigator
// `!keyReservation.contains(key)`, navigator.dart:4049) and its silent
// sibling, stacked duplicate pages:
//
// 1. Pushing a SHELL-BRANCH location (e.g. /you/verify) while a root-level
//    page (/poll/:address, /join) is on top makes go_router clone a SECOND
//    StatefulShellRoute match. Both shell pages share the same
//    ValueKey(route.hashCode) — the assertion in the user's screenshot.
// 2. Rapid double-tap on the JOIN droplet (two taps in one frame, before the
//    route transition starts) pushes TWO /join pages. The lower copy is
//    offstage, so the UI looks fine until back-navigation lands on the
//    zombie duplicate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tessera/app.dart';
import 'package:tessera/shell/app_shell.dart';
import 'package:tessera/spaces/join_screen.dart';
import 'package:tessera/spaces/poll_screen.dart';
import 'package:tessera/spaces/you_verify_screen.dart';

import '../test_dependencies.dart';

const _pollAddr = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets(
    'rapid double-tap on the JOIN droplet pushes exactly one /join page '
    '(no offstage zombie duplicate)',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(TesseraApp(dependencies: deps));
      await tester.pumpAndSettle();

      // Two taps land in the same frame — the real-world rapid double-tap
      // race on a slow web frame, before the push transition covers the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // skipOffstage:false — Navigator keeps a duplicate page OFFSTAGE, so
      // the default finder would miss it and the bug would look "fixed".
      expect(
        find.byType(JoinScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'a double-tap must not stack a second /join page',
      );

      // One pop returns to the shell — no zombie /join beneath.
      // (fullscreenDialog pages get a CLOSE button, not a back arrow.)
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(JoinScreen, skipOffstage: false), findsNothing);
      expect(find.byType(AppShellScaffold), findsOneWidget);
    },
  );

  testWidgets(
    're-firing the JOIN action while /join is already open is a no-op',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(TesseraApp(dependencies: deps));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(JoinScreen), findsOneWidget);

      // The droplet is offstage beneath the opaque /join page, but the same
      // handler can re-fire mid-transition; invoke it directly.
      tester
          .widget<FloatingActionButton>(
            find.byType(FloatingActionButton, skipOffstage: false),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(JoinScreen, skipOffstage: false), findsOneWidget);

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(JoinScreen, skipOffstage: false), findsNothing);
      expect(find.byType(AppShellScaffold), findsOneWidget);
    },
  );

  testWidgets(
    'verify-receipt from a poll page must not crash with the duplicate '
    'page-key assertion (shell-branch push from a root-level page)',
    (tester) async {
      final deps = await buildTestDependencies(
        fetchPolls: () async => [
          testPollInfo(_pollAddr, 'ranked-vote', title: 'Board ranking'),
        ],
      );
      await tester.pumpWidget(TesseraApp(dependencies: deps));
      await tester.pumpAndSettle();

      // The real voter stack: the poll is PUSHED from the vote space, so the
      // shell stays beneath it ([shell(/vote), /poll/:address]).
      final shellContext = tester.element(find.byType(AppShellScaffold));
      GoRouter.of(shellContext).push('/poll/$_pollAddr');
      await tester.pumpAndSettle();
      expect(find.byType(PollScreen), findsOneWidget);

      // The PollScreen receipt flow: push the YOU-space verify location
      // while /poll/:address (a root-level page) is topmost. On the broken
      // router this clones a SECOND shell match whose page shares the first
      // shell's ValueKey(route.hashCode) → navigator.dart:4049 assertion
      // (the user's red screen).
      final context = tester.element(find.byType(PollScreen));
      GoRouter.of(context).push('/you/verify?poll=$_pollAddr&nullifier=0xdead');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(YouVerifyScreen), findsOneWidget);

      // Back returns to the poll — the verify surface is a focused task
      // page, not a space switch.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PollScreen), findsOneWidget);
    },
  );
}
