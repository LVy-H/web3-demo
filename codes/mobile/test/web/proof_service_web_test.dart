@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:tessera/data/services/proof_service_web.dart';

/// In-browser verification of the web ZK path. Exercises the real
/// dart:js_interop round-trip — Dart marshals args to the bundled Semaphore
/// prover, gets a proof back, and that proof VERIFIES against the real Groth16
/// vkey in the same browser. Guards against the "js_interop returned a string"
/// false green. `@TestOn('browser')` means the default VM `flutter test` skips it.
///
/// Run it (needs the bundle + self-hosted artifacts served locally — NO CDN):
///   python3 -m http.server 8099 --directory web   # in codes/mobile
///   flutter test --platform chrome test/web/proof_service_web_test.dart
/// Skips gracefully if the bundle isn't served.
@JS('zkVerifyProof')
external JSPromise<JSBoolean> _zkVerifyProof(JSString proofJson);

@JS('zkGenerateVoteProof')
external JSAny? get _genProbe; // undefined until the bundle script loads

Future<void> _ensureBundleLoaded() async {
  if (_genProbe != null) return;
  final completer = Completer<void>();
  // Served by a local static server (see the test run); plain <script src> is
  // not CORS-restricted, so cross-origin load is fine.
  final script = web.HTMLScriptElement()
    ..src = 'http://localhost:8099/zkprover.js';
  script.onLoad.listen((_) => completer.complete());
  script.onError.listen((_) => completer.completeError('zkprover.js failed to load'));
  web.document.head!.appendChild(script);
  await completer.future.timeout(const Duration(seconds: 30));
}

void main() {
  const seed = 'zkvote-spike-deterministic-seed';
  const members = [
    '3202130587429391573947668392496818956012089007761520528168518742099046353681',
    '22222222222222222222',
  ];

  test('ProofServiceWeb proof round-trips and verifies in-browser', () async {
    try {
      await _ensureBundleLoaded();
    } catch (e) {
      markTestSkipped(
        'zkprover bundle not served — run `python3 -m http.server 8099 '
        '--directory web` first. ($e)',
      );
      return;
    }

    // artifactBase points at the locally-served web/ so the prover loads the
    // self-hosted depth-16 artifacts (web/zk/…) instead of the PSE CDN.
    const svc = ProofServiceWeb(artifactBase: 'http://localhost:8099/');
    final proof = await svc.generateVoteProof(
      identitySeed: seed,
      memberCommitments: members,
      message: 1,
      scope: '0x1111111111111111111111111111111111111111',
    );

    expect(proof.points, hasLength(8));
    // Depth is pinned to the bundled depth-16 circuit (no dynamic CDN depth).
    expect(proof.merkleTreeDepth, 16);

    final ok = await _zkVerifyProof(jsonEncode(proof.toJson()).toJS).toDart;
    expect(ok.toDart, isTrue, reason: 'proof from ProofServiceWeb must verify');
    // No CDN: with `artifactBase` set, the prover loads the self-hosted depth-16
    // artifacts. The local static server's access log shows `GET /zk/
    // semaphore-16.wasm 200` for this run (the PSE CDN is never contacted —
    // `entry.js` only defaults to it when no `wasm`/`zkey` are passed).
  }, timeout: const Timeout(Duration(minutes: 2)));
}
