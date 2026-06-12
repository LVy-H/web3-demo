// Shell test: the JOIN droplet — a CIRCULAR FAB docked into a notch cut out
// of the square bottom bar — plus the three space tabs around it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/app.dart';
import 'package:tessera/spaces/join_screen.dart';
import 'package:tessera/spaces/organize_space_screen.dart';
import 'package:tessera/spaces/vote_space_screen.dart';
import 'package:tessera/spaces/you_space_screen.dart';

import '../test_dependencies.dart';

void main() {
  testWidgets(
    'shell bar is a notched BottomAppBar with the three space tabs '
    '(VOTE / ORGANIZE / YOU) and no legacy NavigationBar',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(TesseraApp(dependencies: deps));
      await tester.pumpAndSettle();

      // Square bar with a circular notch for the droplet.
      final bar = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
      expect(bar.shape, isA<CircularNotchedRectangle>());
      expect(find.byType(NavigationBar), findsNothing);

      // Exactly the three spaces as tabs — JOIN is NOT a tab.
      expect(
        find.descendant(
          of: find.byType(BottomAppBar),
          matching: find.text('VOTE'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomAppBar),
          matching: find.text('ORGANIZE'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomAppBar),
          matching: find.text('YOU'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('JOIN droplet is a circular center-docked FAB', (tester) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.shape, isA<CircleBorder>(), reason: 'the one deliberate circle');
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('JOIN'),
      ),
      findsOneWidget,
      reason: 'the label lives inside the droplet',
    );

    final scaffold = tester.widget<Scaffold>(
      find.ancestor(
        of: find.byType(FloatingActionButton),
        matching: find.byType(Scaffold),
      ).first,
    );
    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.centerDocked,
    );
  });

  testWidgets('tapping the droplet routes to the /join flow', (tester) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(JoinScreen), findsOneWidget);
  });

  testWidgets('tabs switch between the three spaces', (tester) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();
    expect(find.byType(VoteSpaceScreen), findsOneWidget);

    // Bounded pumps — some spaces keep indeterminate progress animations
    // running, so pumpAndSettle would never settle.
    await tester.tap(find.text('ORGANIZE'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OrganizeSpaceScreen), findsOneWidget);

    await tester.tap(find.text('YOU'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(YouSpaceScreen), findsOneWidget);

    await tester.tap(find.text('VOTE'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VoteSpaceScreen), findsOneWidget);
  });
}
