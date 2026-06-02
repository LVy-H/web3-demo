// Phase 11 M1 — WebView on-device proving go/no-go SPIKE (emulator).
//
// Generates a real Semaphore Groth16 vote proof for a small (3-member) test
// group INSIDE a headless `webview_flutter` WebView on the emulator, using the
// BUNDLED depth-16 artifacts (no CDN, no network). The proof JSON is printed to
// stdout so the HOST can verify it independently against the real Groth16 vkey
// via the trusted oracle (`node web_prover/desktop_prover.mjs web/zkprover.js`,
// `verify` op) — verification is deliberately NOT done inside the WebView, to
// keep the oracle independent of the thing under test.
//
// Run:
//   ./dev-stack.sh emu        # boot the emulator (no chain/relayer needed)
//   flutter test integration_test/mobile_prover_spike_test.dart -d emulator-5554
//
// The GO signal: the printed proof has merkleTreeDepth==16, 8 points, and the
// host oracle reports VERIFY=true. This test asserts shape on-device; the vkey
// check is the host step (see the PR / FINDINGS doc).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:tessera/data/services/proof_webview_host.dart';

// Golden inputs: members[0] is the seed's Semaphore commitment (same vector as
// web_prover/verify.mjs + desktop_prover_test), so a correct membership proof
// MUST verify. Padded to a 3-member group per the spec's M1 example.
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

  testWidgets('on-device WebView generates a depth-16 Semaphore proof',
      (tester) async {
    final host = WebViewProverHost();
    addTearDown(host.dispose);

    // init() starts the loopback server + loads the page; await it concurrently
    // while pumping so the platform WebView channel can make progress.
    final initFuture = host.init();
    await _pumpUntil(tester, () => false, timeout: const Duration(seconds: 1));

    // Mount the WebView (offstage 1x1) — JS only runs in an attached WebView.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Offstage(
          offstage: true,
          child: SizedBox(
            width: 1,
            height: 1,
            child: WebViewWidget(controller: host.controller),
          ),
        ),
      ),
    ));

    // Drive the readiness handshake to completion.
    var ready = false;
    initFuture.then((_) => ready = true);
    await _pumpUntil(tester, () => ready, timeout: const Duration(seconds: 60));
    await initFuture; // surface any init error
    expect(ready, isTrue, reason: 'WebView prover host reached readiness');

    // --- PRIMARY: localhost-HTTP artifact delivery (known-good from the host
    //     preflight). This is what locks the GO. ---
    Map<String, dynamic>? proof;
    Object? httpError;
    final httpFuture = host
        .generateProof(
          seed: _seed,
          members: _members,
          message: _message,
          scope: _scope,
          delivery: ArtifactDelivery.localhostHttp,
        )
        .then((p) => proof = p)
        .catchError((e) => httpError = e);
    await _pumpUntil(tester, () => proof != null || httpError != null);

    // ignore: avoid_print
    print('SPIKE httpError=$httpError');
    expect(httpError, isNull,
        reason: 'localhost-HTTP artifact delivery produced a proof in the WebView');
    expect(proof, isNotNull);
    expect(proof!['merkleTreeDepth'], 16,
        reason: 'depth-16 from the bundled artifact');
    expect((proof!['points'] as List).length, 8);

    // The line the HOST captures and pipes into the Node vkey oracle.
    // ignore: avoid_print
    print('SPIKE_PROOF_JSON ${jsonEncode(proof)}');

    // --- SECONDARY (data-point, non-gating): blob-URL delivery. The spec's
    //     preferred production path; ~4.5 MB base64 stresses the Dart→JS string
    //     bridge. Report whether it works; do not fail the spike if it doesn't. ---
    Map<String, dynamic>? blobProof;
    Object? blobError;
    final blobFuture = host
        .generateProof(
          seed: _seed,
          members: _members,
          message: _message,
          scope: _scope,
          delivery: ArtifactDelivery.blobUrl,
        )
        .then((p) => blobProof = p)
        .catchError((e) => blobError = e);
    await _pumpUntil(tester, () => blobProof != null || blobError != null,
        timeout: const Duration(minutes: 3));
    // ignore: avoid_print
    print('SPIKE_BLOB ok=${blobProof != null} depth=${blobProof?['merkleTreeDepth']} '
        'error=$blobError');

    await httpFuture;
    await blobFuture;
  }, timeout: const Timeout(Duration(minutes: 8)));
}
