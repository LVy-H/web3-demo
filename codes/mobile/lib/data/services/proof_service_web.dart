import 'dart:convert';
import 'dart:js_interop';

import '../models/relay_proof.dart';
import 'proof_service.dart';

/// Web [ProofService]: calls the Semaphore v4 prover bundle (web/zkprover.js)
/// over `dart:js_interop`. The bundle is the SAME prover the React app uses and
/// is verified to produce vkey-valid proofs (web_prover/verify.mjs).
@JS('zkGenerateVoteProof')
external JSPromise<JSString> _zkGenerateVoteProof(
  JSString identitySeed,
  JSArray<JSString> memberCommitments,
  JSNumber message,
  JSString scope,
);

class ProofServiceWeb implements ProofService {
  const ProofServiceWeb();

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async {
    final jsMembers = memberCommitments.map((c) => c.toJS).toList().toJS;
    final resultJs = await _zkGenerateVoteProof(
      identitySeed.toJS,
      jsMembers,
      message.toJS,
      scope.toJS,
    ).toDart;
    final map = jsonDecode(resultJs.toDart) as Map<String, dynamic>;
    return RelayProof(
      merkleTreeDepth: (map['merkleTreeDepth'] as num).toInt(),
      merkleTreeRoot: map['merkleTreeRoot'] as String,
      nullifier: map['nullifier'] as String,
      message: map['message'] as String,
      scope: map['scope'] as String,
      points:
          (map['points'] as List).map((e) => e.toString()).toList(growable: false),
    );
  }
}

/// Conditional-import factory hook (web build → this implementation).
ProofService createPlatformProofService() => const ProofServiceWeb();

/// Web has a working prover (snarkjs via js_interop, verified in-browser).
const bool platformProofServiceAvailable = true;
