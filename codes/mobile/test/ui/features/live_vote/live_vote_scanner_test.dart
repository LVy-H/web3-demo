import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/live_vote/live_vote_screen.dart';
import 'package:tessera/ui/features/live_vote/live_vote_view_model.dart';
import 'package:tessera/ui/features/live_vote/qr_scan_sheet.dart';

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '0',
  nullifier: '0',
  message: '1',
  scope: '0',
  points: ['0'],
);

LiveVoteViewModel _vm() => LiveVoteViewModel(
      proof: const FakeProofService(_proof),
      relay: RelayClient(baseUrl: 'http://127.0.0.1:1'),
      reader: ChainReader(
        rpcUrl: 'http://127.0.0.1:1',
        izkPollAbiJson: '[]',
        registryAbiJson: '[]',
        anonVotingAbiJson: '[]',
        registryAddress: '0x0000000000000000000000000000000000000000',
      ),
      pollAddress: '0x2222222222222222222222222222222222222222',
      // Force the ticket/scan stage to render: the production canVote keys off
      // the dart:io prover gate (Platform.isAndroid), false on the Linux test
      // host, which would otherwise show the read-only banner instead.
      canVoteOverride: true,
    );

Widget _host(LiveVoteViewModel vm) => ChangeNotifierProvider.value(
      value: vm,
      child: const MaterialApp(
        home: LiveVoteScreen(address: '0xabc'),
      ),
    );

void main() {
  // The capability gate keys off defaultTargetPlatform, which is `android` in
  // flutter test — so the camera affordance is offered by default.
  testWidgets(
      'mobile: SCAN QR affordance and the paste field both render on needsTicket',
      (tester) async {
    final vm = _vm();
    await tester.pumpWidget(_host(vm));
    await tester.pumpAndSettle();

    expect(cameraScanSupported, isTrue, reason: 'android default in tests');
    expect(find.text('SCAN QR'), findsOneWidget);
    // The paste field is always present (the verified fallback).
    expect(find.text('TICKET / QR LINK'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);
  });

  testWidgets(
      'desktop: SCAN QR affordance is absent, paste field remains the sole input',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final vm = _vm();
    await tester.pumpWidget(_host(vm));
    await tester.pumpAndSettle();

    expect(cameraScanSupported, isFalse, reason: 'linux is not a camera target');
    expect(find.text('SCAN QR'), findsNothing);
    // Paste-based voting is untouched off-mobile.
    expect(find.text('TICKET / QR LINK'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);

    // Reset within the test body (flutter_test asserts foundation debug vars
    // are unset by the time the test returns).
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'a scanned tessera://…?t=… value flows through extractTicket → setTicket → join',
      (tester) async {
    final vm = _vm();
    await tester.pumpWidget(_host(vm));
    await tester.pumpAndSettle();

    // Drive the scan seam directly with a simulated decoded QR value — no real
    // camera. This is exactly what the MobileScanner onDetect callback feeds in.
    final state = tester.state<State<LiveVoteScreen>>(find.byType(LiveVoteScreen));
    (state as dynamic).onScanned(vm, 'tessera://live/0xabc/vote?t=SCANNED-TOK');

    // No new parsing in the scanner: extractTicket (via setTicket) pulled the
    // raw ticket out of the deep-link, same as the paste path would.
    expect(vm.ticket, 'SCANNED-TOK');
    // join() ran: it left needsTicket. With the unreachable test relay it ends
    // in `error`, which honestly proves the wiring fired without a live backend.
    await tester.pump();
    expect(vm.stage, isNot(LiveVoteStage.needsTicket));
  });

  testWidgets('the paste fallback still joins (verified path unchanged)',
      (tester) async {
    final vm = _vm();
    await tester.pumpWidget(_host(vm));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'https://x/live/0xabc/vote?t=PASTED');
    await tester.tap(find.text('JOIN'));
    await tester.pump();

    expect(vm.ticket, 'PASTED');
    expect(vm.stage, isNot(LiveVoteStage.needsTicket));
  });
}
