import 'dart:io' show Platform;

import 'package:core_chain/config.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'proof_service.dart';
import 'proof_service_desktop.dart';
import 'proof_service_mobile.dart';

bool get _desktopProver =>
    AppConfig.desktopProverEnabled &&
    (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

// Android runs the on-device WebView prover (Phase 11 M1 — proof generated in a
// `webview_flutter` WebView from bundled depth-16 artifacts, verified against the
// real Groth16 vkey on an API-31 emulator). iOS rides the same `webview_flutter`
// host but stays unverified-until-a-device, so it remains Unsupported (fenced).
bool get _mobileProver => Platform.isAndroid;

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

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) {
    // Same unsupported error as the int path — survey proving is no more
    // available here than single-question proving.
    throw UnsupportedError(
      'Client-side proof generation is not yet implemented on this platform. '
      'Voting currently works on web (snarkjs via js_interop); the native '
      'mobile/desktop prover is pending (see plan D2 / Open-Q6).',
    );
  }

  @override
  Future<String> deriveCommitment(String identitySeed) {
    throw UnsupportedError(
      'Commitment derivation needs the prover, which is not available on this '
      'platform (web, or desktop with DESKTOP_PROVER configured).',
    );
  }

  @override
  void dispose() {}
}

/// Conditional-import factory hook (non-web build → this stub). Android → the
/// on-device WebView prover; desktop with the Node sidecar configured (SP4) →
/// the sidecar; otherwise the Unsupported stub (iOS, unconfigured desktop).
ProofService createPlatformProofService() {
  if (_mobileProver) return ProofServiceMobile();
  if (_desktopProver) {
    return ProofServiceDesktop(
      nodePath: AppConfig.desktopProverNode,
      sidecarPath: AppConfig.desktopProverSidecar,
      bundlePath: AppConfig.desktopProverBundle,
    );
  }
  return const ProofServiceUnsupported();
}

/// Native client-side proving availability. Web is handled by the web impl.
/// Android is true (the WebView prover ships). Desktop is true ONLY when the
/// opt-in Node sidecar is configured; iOS stays false until a device confirms.
/// Default (unconfigured desktop / iOS) is false, so the vote UI is unchanged
/// where it was before.
bool get platformProofServiceAvailable => _mobileProver || _desktopProver;
