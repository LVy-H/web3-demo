import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zkvote_mobile/data/repositories/verify_repository.dart';
import 'package:zkvote_mobile/ui/features/verify/verify_screen.dart';
import 'package:zkvote_mobile/ui/features/verify/verify_view_model.dart';

class FakeVerifyRepo implements VerifyRepository {
  final bool used;
  FakeVerifyRepo(this.used);
  @override
  Future<bool> isNullifierUsed(String p, String n) async => used;
}

Widget _wrap(bool used, {String? poll, String? nullifier}) => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => VerifyViewModel(FakeVerifyRepo(used)),
        child: VerifyScreen(initialPoll: poll, initialNullifier: nullifier),
      ),
    );

const _poll = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets('renders inputs + verify button', (tester) async {
    await tester.pumpWidget(_wrap(true));
    await tester.pumpAndSettle();
    expect(find.text('VERIFY RECEIPT'), findsOneWidget);
    expect(find.text('POLL ADDRESS'), findsOneWidget);
    expect(find.text('NULLIFIER'), findsOneWidget);
  });

  testWidgets('deep-link prefill auto-verifies → VOTE VERIFIED', (tester) async {
    await tester.pumpWidget(_wrap(true, poll: _poll, nullifier: '12345'));
    await tester.pumpAndSettle();
    expect(find.text('VOTE VERIFIED'), findsOneWidget);
  });

  testWidgets('manual verify with unused nullifier → NOT FOUND', (tester) async {
    await tester.pumpWidget(_wrap(false));
    await tester.enterText(find.byType(TextField).first, _poll);
    await tester.enterText(find.byType(TextField).last, '999');
    await tester.tap(find.text('VERIFY RECEIPT'));
    await tester.pumpAndSettle();
    expect(find.text('NOT FOUND'), findsOneWidget);
  });
}
