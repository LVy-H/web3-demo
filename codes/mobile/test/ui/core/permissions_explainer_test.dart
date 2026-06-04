import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/core/permissions_explainer.dart';
import 'package:tessera/ui/core/poll_roles.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required PollOwnerKind kind,
    bool? reg,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPermissionsExplainerSheet(
                context,
                ownerKind: kind,
                isRegistered: reg,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('leads with privacy and lists the four roles', (tester) async {
    await open(tester, kind: PollOwnerKind.sponsored, reg: null);
    expect(find.text('Your vote is private.'), findsOneWidget);
    expect(find.text('Nobody sees your vote'), findsOneWidget);
    expect(find.text('Who runs the poll'), findsOneWidget);
    expect(find.text('Who can vote'), findsOneWidget);
    expect(find.text('Your access'), findsOneWidget);
    // The anonymity guarantee is stated explicitly.
    expect(find.textContaining('not even the'), findsOneWidget);
    // Sponsored owner-kind → relayer-run wording.
    expect(find.textContaining('relayer runs it'), findsOneWidget);
  });

  testWidgets('registered voter sees the "you can cast" wording', (
    tester,
  ) async {
    await open(tester, kind: PollOwnerKind.you, reg: true);
    expect(find.textContaining('you can cast one anonymous'), findsOneWidget);
  });

  testWidgets('not-registered voter is told to join', (tester) async {
    await open(tester, kind: PollOwnerKind.sponsored, reg: false);
    expect(find.textContaining('join the poll'), findsOneWidget);
  });
}
