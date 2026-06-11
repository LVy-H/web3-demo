import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/widgets/results_bars.dart';

/// Pump the widget in isolation so `find.byType(FractionallySizedBox)` returns
/// exactly one fill per option (no surrounding screen chrome).
Widget _host(List<ResultOption> options, {BigInt? total, String? emptyLabel}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: ResultsBars(
              options: options,
              total: total,
              emptyLabel: emptyLabel ?? 'No votes yet',
            ),
          ),
        ),
      ),
    );

ResultOption _opt(String label, int count) =>
    (label: label, count: BigInt.from(count));

void main() {
  group('ResultsBars', () {
    testWidgets('renders correct bar fractions from counts', (tester) async {
      await tester.pumpWidget(_host([
        _opt('Yes', 3),
        _opt('No', 1),
        _opt('Abstain', 0),
      ]));
      await tester.pumpAndSettle();

      final fills = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(fills, hasLength(3)); // one fill per option
      expect(fills[0].widthFactor, closeTo(0.75, 1e-9)); // 3/4
      expect(fills[1].widthFactor, closeTo(0.25, 1e-9)); // 1/4
      expect(fills[2].widthFactor, closeTo(0.0, 1e-9)); // 0/4

      // Visible label/count/% are preserved (screen tests rely on these).
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('explicit total overrides the option sum', (tester) async {
      // Sum is 3 but total says 10 → leader fills 30%, not 100%.
      await tester.pumpWidget(_host(
        [_opt('A', 3), _opt('B', 0)],
        total: BigInt.from(10),
      ));
      await tester.pumpAndSettle();

      final fills = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(fills[0].widthFactor, closeTo(0.3, 1e-9));
      expect(find.text('30.0%'), findsOneWidget);
    });

    testWidgets('count exceeding total clamps to widthFactor 1.0 / 100.0%',
        (tester) async {
      // Approval polls pass total = voter count, but per-option APPROVALS can
      // exceed it (a voter approving many options). The bar must clamp to full
      // width and 100.0%, never overflow past 1.0.
      await tester.pumpWidget(_host(
        [_opt('A', 7), _opt('B', 2)],
        total: BigInt.from(4), // 4 voters, but 7 approvals for A
      ));
      await tester.pumpAndSettle();

      final fills = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(fills[0].widthFactor, closeTo(1.0, 1e-9)); // 7/4 clamped to 1.0
      expect(find.text('100.0%'), findsOneWidget);
      // The under-total option is unaffected.
      expect(fills[1].widthFactor, closeTo(0.5, 1e-9)); // 2/4
    });

    testWidgets('highlights the single leader', (tester) async {
      await tester.pumpWidget(_host([
        _opt('Winner', 5),
        _opt('Runner-up', 2),
      ]));
      await tester.pumpAndSettle();

      // Exactly one winner marker, and it's the leading option.
      expect(find.byKey(ResultsBars.winnerKey), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets(
        'highlightLeader: false crowns nobody even with a clear leader '
        '(ranked first-prefs are NOT the winner)', (tester) async {
      // The ranked (M4) screen passes highlightLeader: false because these bars
      // are the ROUND-1 first-preference tally — the first-pref leader is
      // frequently NOT the instant-runoff winner, and the spec forbids any chart
      // treating max(results) as the outcome. A clear leader (5 vs 2) must still
      // get NO trophy.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ResultsBars(
                highlightLeader: false,
                options: [_opt('Front-runner', 5), _opt('Other', 2)],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(ResultsBars.winnerKey), findsNothing,
          reason: 'no winner marker when highlightLeader is false');
      expect(find.byIcon(Icons.emoji_events), findsNothing,
          reason: 'no trophy on the first-pref leader');
      // Bars still render — only the highlight is suppressed.
      expect(find.byType(FractionallySizedBox), findsNWidgets(2));
    });

    testWidgets('a tie shows no single winner', (tester) async {
      await tester.pumpWidget(_host([
        _opt('A', 4),
        _opt('B', 4),
        _opt('C', 1),
      ]));
      await tester.pumpAndSettle();

      expect(find.byKey(ResultsBars.winnerKey), findsNothing);
      // Bars still render for a tie — only the highlight is withheld.
      expect(find.byType(FractionallySizedBox), findsNWidgets(3));
    });

    testWidgets('zero total shows the empty state, no bars, no winner',
        (tester) async {
      await tester.pumpWidget(_host([
        _opt('A', 0),
        _opt('B', 0),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('No votes yet'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing); // no divide-by-zero
      expect(find.byKey(ResultsBars.winnerKey), findsNothing);
    });

    testWidgets('zero total uses a custom empty label when provided',
        (tester) async {
      await tester.pumpWidget(_host(
        [_opt('A', 0)],
        emptyLabel: 'Votes are hidden until voters reveal after voting ends.',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Votes are hidden until voters reveal after voting ends.'),
          findsOneWidget);
      expect(find.text('No votes yet'), findsNothing);
    });

    testWidgets('huge BigInt counts do not overflow the layout',
        (tester) async {
      // uint256-scale counts (78-digit strings) with no soft-wrap points: the
      // count Text must shrink (Flexible + ellipsis) rather than blow out the row.
      final big = BigInt.parse('1${'0' * 76}'); // ~1e76, within uint256
      await tester.pumpWidget(_host([
        (label: 'A very long option label that should also stay on one line',
            count: big * BigInt.two),
        (label: 'Beta', count: big),
      ]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // no RenderFlex overflow
      // Fractions are still computed exactly from the BigInts: 2/3 and 1/3.
      final fills = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(fills, hasLength(2));
      expect(fills[0].widthFactor, closeTo(2 / 3, 1e-6));
      expect(fills[1].widthFactor, closeTo(1 / 3, 1e-6));
      // The bigger count is the strict leader.
      expect(find.byKey(ResultsBars.winnerKey), findsOneWidget);
    });
  });
}
