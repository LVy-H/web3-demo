// Phase 11 M2 — ProofServiceMobile end-to-end verification (emulator).
//
// Unlike `mobile_prover_spike_test.dart` (which drives the WebViewProverHost
// engine directly), this exercises the PRODUCTION wiring: it constructs the
// `ProofServiceMobile` the factory returns on Android, mounts its `hostView`
// (the SAME 1×1 offstage WebView the app shell mounts via MaterialApp.builder),
// and calls the `ProofService` interface — `generateVoteProof()` and
// `deriveCommitment()`. Both outputs are printed so the HOST can verify them:
//   - the RelayProof against the real Groth16 vkey (desktop_prover.mjs verify)
//   - the commitment against `zkCommitment(seed)` computed host-side.
//
// Run:
//   ./dev-stack.sh emu        # or boot the API-31 Pixelhi AVD (see FINDINGS)
//   flutter test integration_test/mobile_proof_service_test.dart -d emulator-5554
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/services/proof_service_mobile.dart';

// Same golden vector as the spike + web_prover/verify.mjs: members[0] is the
// seed's commitment, so a correct membership proof MUST verify.
const _seed = 'zkvote-spike-deterministic-seed';
const _seedCommitment =
    '3202130587429391573947668392496818956012089007761520528168518742099046353681';
const _members = [_seedCommitment, '22222222222222222222', '33333333333333333333'];
const _message = 1;
const _scope = '0x1111111111111111111111111111111111111111';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(minutes: 3)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (done()) return;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ProofServiceMobile proves + derives commitment via its mounted host',
      (tester) async {
    final service = ProofServiceMobile();
    addTearDown(service.dispose);

    // Mount the SERVICE's own hostView — the exact widget production mounts in
    // MaterialApp.builder. This is what makes the test verify the M2 wiring (the
    // service drives init() lazily on first call), not just the engine.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: service.hostView),
    ));
    await _pumpUntil(tester, () => false, timeout: const Duration(seconds: 1));

    // --- deriveCommitment (NEW on-device op; never run in the M1 spike) ---
    String? commitment;
    Object? commitErr;
    final commitFuture = service
        .deriveCommitment(_seed)
        .then((c) => commitment = c)
        .catchError((e) => commitErr = e);
    await _pumpUntil(tester, () => commitment != null || commitErr != null,
        timeout: const Duration(seconds: 90));
    // ignore: avoid_print
    print('SVC_COMMITMENT value=$commitment error=$commitErr');
    expect(commitErr, isNull, reason: 'deriveCommitment ran in the WebView');
    expect(commitment, _seedCommitment,
        reason: 'on-device commitment matches the golden vector');
    await commitFuture;

    // --- generateVoteProof through the ProofService interface ---
    RelayProof? proof;
    Object? proofErr;
    final proofFuture = service
        .generateVoteProof(
          identitySeed: _seed,
          memberCommitments: _members,
          message: _message,
          scope: _scope,
        )
        .then((p) => proof = p)
        .catchError((e) => proofErr = e);
    await _pumpUntil(tester, () => proof != null || proofErr != null);
    // ignore: avoid_print
    print('SVC proofError=$proofErr');
    expect(proofErr, isNull, reason: 'generateVoteProof produced a proof');
    expect(proof, isNotNull);
    expect(proof!.merkleTreeDepth, 16);
    expect(proof!.points.length, 8);

    // The line the HOST captures and pipes into the Node vkey oracle.
    // ignore: avoid_print
    print('SVC_PROOF_JSON ${jsonEncode(proof!.toJson())}');
    await proofFuture;
  }, timeout: const Timeout(Duration(minutes: 8)));
}
