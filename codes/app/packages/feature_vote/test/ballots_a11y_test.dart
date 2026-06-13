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
  });
}
