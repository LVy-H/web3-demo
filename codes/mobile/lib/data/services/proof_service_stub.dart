import '../models/relay_proof.dart';
import 'proof_service.dart';

/// Native (mobile/desktop) [ProofService] placeholder. Client-side Semaphore
/// proving on native targets is the UNRESOLVED part of the plan (D2/Open-Q6):
/// `webview_flutter` doesn't cover Linux/Windows, so the native path (webview
/// vs Rust-FFI) is deferred pending the desktop-voting scope decision. Until
/// then, native voting throws a clear, actionable error instead of a false green.
class ProofServiceUnsupported implements ProofService {
  const ProofServiceUnsupported();

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) {
    throw UnsupportedError(
      'Client-side proof generation is not yet implemented on this platform. '
      'Voting currently works on web (snarkjs via js_interop); the native '
      'mobile/desktop prover is pending (see plan D2 / Open-Q6).',
    );
  }
}

/// Conditional-import factory hook (non-web build → this stub).
ProofService createPlatformProofService() => const ProofServiceUnsupported();
