// The composed YOU space: all sections render off one injected dependency
// set, and the receipt → verify hand-off crosses the composition.
import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pollA = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets('renders pass, receipts and settings; receipt opens verify '
      'pre-filled', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <(String?, String?)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: YouSpaceView(
          identityStore: InMemoryIdentityStore('0xdeadbeef'),
          onPassChanged: () async {},
          receiptsStore: InMemoryReceiptsStore([
            VoteReceipt(
              pollAddress: pollA,
              pollTitle: 'Club budget 2026',
              receiptCode: '999',
              savedAt: DateTime(2026, 6, 1),
            ),
          ]),
          onOpenVerify: (poll, code) => opened.add((poll, code)),
          networkConfigStore: InMemoryNetworkConfigStore(),
          onNetworkConfigChanged: () async {},
          checkChain: () async => true,
          checkRelayer: () async => true,
          canProve: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VOTING PASS'), findsOneWidget);
    expect(find.text('Active on this device'), findsOneWidget);
    expect(find.text('RECEIPTS'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);

    await tester.tap(find.text('Club budget 2026'));
    expect(opened, [(pollA, '999')]);
  });
}
