// Accessibility tests for the ballot inputs — the voter's critical path.
// Screen-reader users pick options and split points here; the tiles and the
// quadratic steppers must announce their role, state and which option they
// belong to.
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('option tile semantics', () {
    testWidgets('single-choice options announce as selectable buttons that '
        'flip to selected', (tester) async {
      final handle = tester.ensureSemantics();
      var spec = const SingleChoice(0);
      await tester.pumpWidget(
        _host(
          SingleChoiceBallot(
            options: const ['Alpha', 'Beta'],
            onChanged: (s) => spec = s as SingleChoice,
          ),
        ),
      );

      // Before any tap: the option is a selectable button, not yet selected.
      expect(
        tester.getSemantics(find.text('Alpha')),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          label: 'Alpha',
        ),
        reason: 'option tile must expose a selectable button to assistive tech',
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(spec.optionIndex, 0);

      expect(
        tester.getSemantics(find.text('Alpha')),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('approval options expose selected state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(ApprovalBallot(options: const ['One', 'Two'], onChanged: (_) {})),
      );
      expect(
        tester.getSemantics(find.text('One')),
        isSemantics(hasSelectedState: true, isSelected: false),
      );
      handle.dispose();
    });
  });

  group('quadratic stepper semantics', () {
    testWidgets('each stepper button names its option and direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          QuadraticBallot(
            options: const ['Apples', 'Pears'],
            onChanged: (_) {},
          ),
        ),
      );

      // A screen reader must be able to tell apart "add to Apples" from
      // "add to Pears" — bare + / − icons announce nothing.
      expect(find.byTooltip('Add a point to Apples'), findsOneWidget);
      expect(find.byTooltip('Remove a point from Apples'), findsOneWidget);
      expect(find.byTooltip('Add a point to Pears'), findsOneWidget);
      expect(find.byTooltip('Remove a point from Pears'), findsOneWidget);
    });

    testWidgets('each option row announces its current allocation', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          QuadraticBallot(
            options: const ['Apples', 'Pears'],
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Apples: 0 points'), findsOneWidget);
      await tester.tap(find.byTooltip('Add a point to Apples'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Apples: 1 points'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'a multi-digit allocation does not overflow or clip the count box at '
      'large text scale',
      (tester) async {
        // A render-time regression invisible to logic tests: the per-option
        // count box was a fixed 28dp wide, so a two-/three-digit allocation at
        // a large OS text scale clipped (or struck a RenderFlex overflow).
        tester.view.physicalSize = const Size(520, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(
                body: QuadraticBallot(
                  options: const ['Apples', 'Pears'],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        // Drive the allocation into double digits (budget caps a single
        // option at 10 → cost 100 = all credits).
        for (var i = 0; i < 10; i++) {
          await tester.tap(find.byKey(QuadraticBallot.plusKey(0)));
          await tester.pumpAndSettle();
        }

        // The two-digit count is shown and the row laid out with no overflow.
        expect(find.text('10'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The count sits inside a FittedBox(scaleDown) so that a value wider
        // than its box (a two-digit count at 2x scale is wider than the old
        // 28dp box) is shrunk to fit instead of being clipped, and the box
        // itself stays within the widened 40dp slot — no overflow, no clip.
        final fittedBox = find.ancestor(
          of: find.text('10'),
          matching: find.byType(FittedBox),
        );
        expect(fittedBox, findsOneWidget);
        expect(
          tester.widget<FittedBox>(fittedBox).fit,
          BoxFit.scaleDown,
          reason: 'the count must scale down to fit, never clip',
        );
        expect(
          tester.getSize(fittedBox).width,
          lessThanOrEqualTo(40.0),
          reason: 'the count box stays within its widened 40dp slot',
        );
      },
    );
  });
}
