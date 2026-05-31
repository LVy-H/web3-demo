import '../models/relay_proof.dart';

/// Generates a Semaphore v4 vote proof.
///
/// Dart has no mature native Semaphore prover, so the crypto runs in JS
/// (Semaphore v4 + snarkjs) hosted by a platform-specific implementation:
///   - web:    `dart:js_interop` calling the bundled Semaphore JS
///   - mobile: `webview_flutter` hosting the same JS bundle
///
/// The crypto is proven ONLY against the real Groth16 verifier — local Hardhat
/// uses MockSemaphoreVerifier (always-true), so an on-chain "success" there is
/// meaningless. The de-risk spike confirmed `generateProof → verifyProof == true`
/// with the real vkey; its output is captured in
/// `test/fixtures/zk_proof_vector.json` and matches [RelayProof].
abstract class ProofService {
  /// Build a membership proof for the identity derived from [identitySeed],
  /// over the group of [memberCommitments] (decimal strings, from on-chain
  /// `VoterRegistered` events), casting option [message], scoped to [scope]
  /// (the poll address). Returns the [RelayProof] to POST to the relayer.
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  });
}

/// A deterministic [ProofService] that returns a fixed, pre-verified proof.
/// Used by UI/screen tests and as the seam's stand-in until the web/mobile JS
/// implementations land. NOT for production — it ignores its inputs.
class FakeProofService implements ProofService {
  final RelayProof proof;
  const FakeProofService(this.proof);

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async =>
      proof;
}
