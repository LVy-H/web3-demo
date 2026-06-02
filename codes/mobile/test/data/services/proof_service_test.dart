import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/services/proof_service.dart';

/// Validates that [RelayProof] faithfully carries a REAL Semaphore v4 proof
/// (the one verified against the real Groth16 vkey in the de-risk spike) and
/// that the [ProofService] seam returns it unchanged. Locks the output shape
/// the web/mobile JS implementations must reproduce.
void main() {
  final vector = jsonDecode(
    File('test/fixtures/zk_proof_vector.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final pv = vector['proof'] as Map<String, dynamic>;

  RelayProof goldenProof() => RelayProof(
        merkleTreeDepth: (pv['merkleTreeDepth'] as num).toInt(),
        merkleTreeRoot: pv['merkleTreeRoot'] as String,
        nullifier: pv['nullifier'] as String,
        message: pv['message'] as String,
        scope: pv['scope'] as String,
        points: (pv['points'] as List).cast<String>(),
      );

  test('the spike proof verified against the real vkey', () {
    expect(vector['verifyProof'], isTrue);
  });

  test('RelayProof represents a real Semaphore proof (8 points, int depth)', () {
    final p = goldenProof();
    expect(p.points, hasLength(8));
    expect(p.merkleTreeDepth, isA<int>());
    // field elements are decimal strings the relayer re-parses with BigInt(...)
    expect(BigInt.tryParse(p.nullifier), isNotNull);
    expect(BigInt.tryParse(p.scope), isNotNull);
  });

  test('toJson emits the relayer body shape (number depth, string elements)', () {
    final j = goldenProof().toJson();
    expect(j['merkleTreeDepth'], isA<int>());
    expect(j['merkleTreeRoot'], isA<String>());
    expect(j['points'], isA<List<String>>());
    expect((j['points'] as List), hasLength(8));
  });

  test('FakeProofService returns the configured proof regardless of inputs',
      () async {
    final svc = FakeProofService(goldenProof());
    final out = await svc.generateVoteProof(
      identitySeed: 'ignored',
      memberCommitments: const ['1', '2'],
      message: 0,
      scope: '0xdead',
    );
    expect(out.nullifier, goldenProof().nullifier);
    expect(out.points, goldenProof().points);
  });
}
