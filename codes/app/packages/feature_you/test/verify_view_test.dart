// Verify surface (R3): counted / not-found / error verdicts with
// jargon-free copy, query-param prefill auto-run, local validation, and the
// no-pass read-only contract (nothing identity-shaped is injected at all).
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const poll = '0x1111111111111111111111111111111111111111';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required ReceiptCheck checkReceipt,
    PollTitleLookup? lookupPollTitle,
    String? initialPoll,
    String? initialCode,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyView(
          checkReceipt: checkReceipt,
          lookupPollTitle: lookupPollTitle,
          initialPollAddress: initialPoll,
          initialReceiptCode: initialCode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterAndCheck(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), poll);
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('CHECK RECEIPT'));
    await tester.pumpAndSettle();
  }

  testWidgets('counted receipt shows the poll title, jargon-free', (
    tester,
  ) async {
    String? checkedPoll;
    String? checkedCode;
    await pump(
      tester,
      checkReceipt: (p, c) async {
        checkedPoll = p;
        checkedCode = c;
        return true;
      },
      lookupPollTitle: (_) async => 'Club budget 2026',
    );
    await enterAndCheck(tester);

    expect(checkedPoll, poll);
    expect(checkedCode, '12345');
    expect(find.text('COUNTED'), findsOneWidget);
    expect(
      find.textContaining('This receipt is counted in “Club budget 2026”'),
      findsOneWidget,
    );
    expect(find.textContaining('nullifier'), findsNothing);
    expect(find.textContaining('Semaphore'), findsNothing);
  });

  testWidgets('a failing title lookup still verifies', (tester) async {
    await pump(
      tester,
      checkReceipt: (_, _) async => true,
      lookupPollTitle: (_) async => throw StateError('registry down'),
    );
    await enterAndCheck(tester);

    expect(find.text('COUNTED'), findsOneWidget);
    expect(
      find.textContaining('This receipt is counted in this poll'),
      findsOneWidget,
    );
  });

  testWidgets('unrecorded receipt shows NOT FOUND', (tester) async {
    await pump(tester, checkReceipt: (_, _) async => false);
    await enterAndCheck(tester);

    expect(find.text('NOT FOUND'), findsOneWidget);
    expect(
      find.textContaining('this receipt isn’t recorded in this poll'),
      findsOneWidget,
    );
  });

  testWidgets('network failure shows the honest error state', (tester) async {
    await pump(
      tester,
      checkReceipt: (_, _) async => throw StateError('rpc unreachable'),
    );
    await enterAndCheck(tester);

    expect(find.text('COULDN’T CHECK'), findsOneWidget);
    expect(find.textContaining('rpc unreachable'), findsOneWidget);
  });

  testWidgets('prefilled deep link auto-runs the check', (tester) async {
    var calls = 0;
    await pump(
      tester,
      checkReceipt: (_, _) async {
        calls++;
        return true;
      },
      initialPoll: poll,
      initialCode: '777',
    );

    expect(calls, 1, reason: '?poll=&nullifier= prefill must auto-check');
    expect(find.text('COUNTED'), findsOneWidget);
  });

  testWidgets('invalid inputs are rejected locally, before any chain call', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      checkReceipt: (_, _) async {
        calls++;
        return true;
      },
    );

    await tester.enterText(find.byType(TextField).at(0), 'not-an-address');
    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.tap(find.text('CHECK RECEIPT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('poll address'), findsWidgets);
    expect(calls, 0);

    await tester.enterText(find.byType(TextField).at(0), poll);
    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.tap(find.text('CHECK RECEIPT'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('doesn’t look like a receipt code'),
      findsOneWidget,
    );
    expect(calls, 0);
  });
}
