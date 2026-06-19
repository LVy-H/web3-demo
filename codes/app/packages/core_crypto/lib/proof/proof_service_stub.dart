import 'package:core_domain/models/relay_proof.dart';
import 'proof_service.dart';

/// Phase-1 placeholder [ProofService].
///
/// The 2026-06-19 redesign removed the Semaphore/Groth16 provers (web / mobile
/// WebView / desktop sidecar) and their SNARK artifacts. Secret ballots will use
/// **server-issued blind-signature credentials**, not client-side ZK proofs
/// (see `docs/superpowers/specs/2026-06-19-tessera-system-design.md`). Until the
/// server credential path lands (Phase 4), proving is **fenced**: it throws a
/// clear error instead of a false green.
class ProofServiceUnsupported implements ProofService {
  const ProofServiceUnsupported();

  static const _msg =
      'Client-side ZK proving was removed in the 2026-06-19 redesign. Secret '
      'ballots will use server-issued blind-signature credentials (Phase 4).';

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) =>
      throw UnsupportedError(_msg);

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) =>
      throw UnsupportedError(_msg);

  @override
  Future<String> deriveCommitment(String identitySeed) =>
      throw UnsupportedError(_msg);

  @override
  void dispose() {}
}

/// Factory hook (all platforms): the fenced stub until secret ballots move to
/// server-issued blind-signature credentials (Phase 4).
ProofService createPlatformProofService() => const ProofServiceUnsupported();

/// Client-side proving availability — false everywhere now (proving is moving to
/// server-issued credentials).
bool get platformProofServiceAvailable => false;
