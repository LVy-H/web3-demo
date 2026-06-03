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

/// Second binding to the SAME `zkGenerateVoteProof` global, typed so [message]
/// crosses as a JS **string** instead of a JS number. The JS prover does
/// `BigInt(message)` (it accepts number|string|bigint), so a wide decimal-string
/// commitment round-trips losslessly — a JS number would silently cap at ~53
/// bits. No JS-bundle change is needed for this.
@JS('zkGenerateVoteProof')
external JSPromise<JSString> _zkGenerateVoteProofWide(
  JSString identitySeed,
  JSArray<JSString> memberCommitments,
  JSString message,
  JSString scope,
);

@JS('zkCommitment')
external JSString _zkCommitment(JSString seed);

class ProofServiceWeb implements ProofService {
  const ProofServiceWeb();

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async {
    // The int (shipped-modules) path: message crosses as a JS NUMBER, exactly
    // as before. Kept byte-identical — the JSNumber→JSString flip is NOT covered
    // by `flutter test`, so we don't touch the verified path's emitted behavior.
    final jsMembers = memberCommitments.map((c) => c.toJS).toList().toJS;
    final resultJs = await _zkGenerateVoteProof(
      identitySeed.toJS,
      jsMembers,
      message.toJS,
      scope.toJS,
    ).toDart;
    return _parseProof(resultJs);
  }

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) async {
    // The wide (survey) path: message crosses as a JS STRING. The JS prover does
    // `BigInt(message)`, so a 248-bit decimal commitment survives intact.
    final jsMembers = memberCommitments.map((c) => c.toJS).toList().toJS;
    final resultJs = await _zkGenerateVoteProofWide(
      identitySeed.toJS,
      jsMembers,
      message.toJS,
      scope.toJS,
    ).toDart;
    return _parseProof(resultJs);
  }

  RelayProof _parseProof(JSString resultJs) {
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

  @override
  Future<String> deriveCommitment(String identitySeed) async =>
      _zkCommitment(identitySeed.toJS).toDart;

  @override
  void dispose() {}
}

/// Conditional-import factory hook (web build → this implementation).
ProofService createPlatformProofService() => const ProofServiceWeb();

/// Web has a working prover (snarkjs via js_interop, verified in-browser).
const bool platformProofServiceAvailable = true;
