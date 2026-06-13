// Receipts archive (R3): list rendering, the receipt → verify-prefill
// hand-off, the blank-check entry and the empty state.
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pollA = '0x1111111111111111111111111111111111111111';
const pollB = '0x2222222222222222222222222222222222222222';

void main() {
  late List<(String?, String?)> opened;

  Future<void> pump(WidgetTester tester, ReceiptsStore store) async {
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReceiptsSection(
              store: store,
              onOpenVerify: (poll, code) => opened.add((poll, code)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists saved receipts and opens verify pre-filled on tap', (
    tester,
  ) async {
    final store = InMemoryReceiptsStore([
      VoteReceipt(
        pollAddress: pollA,
        pollTitle: 'Club budget 2026',
        receiptCode: '987654321',
        savedAt: DateTime(2026, 6, 1),
      ),
      VoteReceipt(
        pollAddress: pollB,
        pollTitle: 'Board election',
        receiptCode: '123456789',
        savedAt: DateTime(2026, 5, 20),
      ),
    ]);
    await pump(tester, store);

    expect(find.text('Club budget 2026'), findsOneWidget);
    expect(find.text('Board election'), findsOneWidget);

    await tester.tap(find.text('Club budget 2026'));
    expect(opened, [(pollA, '987654321')]);
  });

  testWidgets('CHECK A RECEIPT opens verify with no prefill', (tester) async {
    await pump(tester, InMemoryReceiptsStore());

    await tester.tap(find.text('CHECK A RECEIPT'));
    expect(opened, [(null, null)]);
  });

  testWidgets('empty archive explains where receipts come from', (
    tester,
  ) async {
    await pump(tester, InMemoryReceiptsStore());

    expect(find.textContaining('No receipts yet'), findsOneWidget);
  });

  testWidgets(
    'a throwing store shows an honest error, not a false empty state',
    (tester) async {
      await pump(tester, _ThrowingReceiptsStore());

      // The whole point of receipts is "check your vote counted" — telling a
      // voter "No receipts yet" when the store actually FAILED is a trust gap.
      expect(find.textContaining('No receipts yet'), findsNothing);
      expect(
        find.textContaining('Couldn’t load your receipts'),
        findsOneWidget,
      );
      expect(find.text('TRY AGAIN'), findsOneWidget);
    },
  );

  testWidgets('retry after a load failure recovers the list', (tester) async {
    final store = _FlakyReceiptsStore([
      VoteReceipt(
        pollAddress: pollA,
        pollTitle: 'Club budget 2026',
        receiptCode: '987654321',
        savedAt: DateTime(2026, 6, 1),
      ),
    ]);
    await pump(tester, store);

    // First load threw → error state, no false empty.
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('Club budget 2026'), findsNothing);

    store.failNext = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();

    expect(find.text('TRY AGAIN'), findsNothing);
    expect(find.text('Club budget 2026'), findsOneWidget);
  });
}

class _ThrowingReceiptsStore implements ReceiptsStore {
  @override
  Future<List<VoteReceipt>> loadAll() async =>
      throw StateError('secure storage unavailable');
  @override
  Future<void> save(VoteReceipt receipt) async {}
  @override
  Future<void> remove(String pollAddress, String receiptCode) async {}
  @override
  Future<void> clear() async {}
}

/// Throws on the first load, then succeeds — exercises the retry path.
class _FlakyReceiptsStore implements ReceiptsStore {
  _FlakyReceiptsStore(this._receipts);
  final List<VoteReceipt> _receipts;
  bool failNext = true;
  @override
  Future<List<VoteReceipt>> loadAll() async {
    if (failNext) throw StateError('secure storage unavailable');
    return List.unmodifiable(_receipts);
  }

  @override
  Future<void> save(VoteReceipt receipt) async {}
  @override
  Future<void> remove(String pollAddress, String receiptCode) async {}
  @override
  Future<void> clear() async {}
}
