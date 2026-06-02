import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/proof_service_desktop.dart';

/// SP4 gate: the desktop Node sidecar generates a Semaphore proof that VERIFIES
/// against the real Groth16 vkey (the local MockSemaphoreVerifier would accept
/// anything — this checks the real crypto). Reuses the exact same web/zkprover.js
/// bundle the web path uses, run under Node.
///
/// Opt-in (needs Node + network for the CDN artifacts): run with
///   RUN_DESKTOP_PROVER=1 flutter test test/integration/desktop_prover_test.dart
/// Skips otherwise, so CI/offline runs stay green.
void main() {
  const sidecar = 'web_prover/desktop_prover.mjs';
  const bundle = 'web/zkprover.js';

  final enabled = Platform.environment['RUN_DESKTOP_PROVER'] == '1';
  if (!enabled || !File(sidecar).existsSync() || !File(bundle).existsSync()) {
    test('desktop prover (opt-in)', () {
      markTestSkipped('set RUN_DESKTOP_PROVER=1 with Node + network to run');
    }, skip: true);
    return;
  }

  test('desktop sidecar proof verifies against the real vkey', () async {
    final prover = ProofServiceDesktop(
      nodePath: 'node',
      sidecarPath: sidecar,
      bundlePath: bundle,
    );
    addTearDown(prover.dispose);

    // Same golden inputs as web_prover/verify.mjs: the seed's commitment is in
    // the group, so a correct proof must verify.
    const seed = 'zkvote-spike-deterministic-seed';
    const members = [
      '3202130587429391573947668392496818956012089007761520528168518742099046353681',
      '22222222222222222222',
    ];
    final proof = await prover.generateVoteProof(
      identitySeed: seed,
      memberCommitments: members,
      message: 1,
      scope: '0x1111111111111111111111111111111111111111',
    );
    expect(proof.points.length, 8);

    final valid = await prover.verifyProof(proof);
    expect(valid, isTrue,
        reason: 'desktop-generated proof verifies against the real Groth16 vkey');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
