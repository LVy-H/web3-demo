import 'package:core_domain/models/relay_proof.dart';
import 'proof_service.dart';

/// Phase-1 placeholder [ProofService].
///
/// The 2026-06-19 redesign removed the Semaphore/Groth16 provers (web / mobile
/// WebView / desktop sidecar) and their SNARK artifacts. Secret ballots use
/// **server-issued blind-signature credentials**, not client-side ZK proofs
/// (see `docs/superpowers/specs/2026-06-19-tessera-system-design.md`). That
/// credential path has LANDED (Phase 4): the pure-Dart RSABSSA client is
/// `core_crypto/lib/credentials/blind_rsa.dart`, the voter handshake is
/// `feature_vote/.../secret_ballot_credential.dart` (wired into the secret-mode
/// branch of `server_voter_port_adapter.dart`), and byte-exact interop with the
/// server issuer is proven by
/// `core_relay/test/server_client_secret_live_test.dart`. This ZK [ProofService]
/// stub therefore stays permanently **fenced** — it is replaced by credentials,
/// not revived — and throws a clear error rather than a false green.
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
  }) => throw UnsupportedError(_msg);

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) => throw UnsupportedError(_msg);

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
