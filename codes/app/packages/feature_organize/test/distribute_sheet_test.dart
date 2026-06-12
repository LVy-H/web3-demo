// The DISTRIBUTE share sheet: QR + copy-link always, the NFC tile only on
// hardware that has the radio (spec §4.3), and the link is feature_join's
// canonical poll deep link so JOIN reads it straight back.
import 'package:feature_join/feature_join.dart'
    show PollTarget, parseJoinInput, shareLinkForPoll;
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pollAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
final String _link = shareLinkForPoll(_pollAddress, module: 'anon-vote');

Future<void> _pump(WidgetTester tester, {required bool nfcAvailable}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DistributeSheet(shareLink: _link, nfcAvailable: nfcAvailable),
        ),
      ),
    );

void main() {
  testWidgets('shows the QR and the canonical link the JOIN grammar reads '
      'back to the same poll', (tester) async {
    await _pump(tester, nfcAvailable: false);

    expect(find.byKey(DistributeSheet.qrKey), findsOneWidget);
    expect(find.text(_link), findsOneWidget);

    final target = parseJoinInput(_link);
    expect(target, isA<PollTarget>());
    expect(
      (target as PollTarget).address.toLowerCase(),
      _pollAddress.toLowerCase(),
    );
  });

  testWidgets('COPY LINK puts the share link on the clipboard and '
      'confirms it', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, nfcAvailable: false);
    await tester.tap(find.byKey(DistributeSheet.copyLinkKey));
    await tester.pump();

    final setData = calls.where((c) => c.method == 'Clipboard.setData');
    expect(setData, hasLength(1));
    expect((setData.single.arguments as Map)['text'], _link);
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('no NFC hardware → the NFC tile is dropped entirely', (
    tester,
  ) async {
    await _pump(tester, nfcAvailable: false);
    expect(find.byKey(DistributeSheet.nfcTileKey), findsNothing);
  });

  testWidgets('NFC hardware present → the tile appears with hold-to-share '
      'instructions', (tester) async {
    await _pump(tester, nfcAvailable: true);
    expect(find.byKey(DistributeSheet.nfcTileKey), findsOneWidget);
    expect(find.textContaining('hold the voter’s phone'), findsOneWidget);
  });
}
