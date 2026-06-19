import 'proof_service.dart';
import 'proof_service_stub.dart';

/// Returns the [ProofService] for the current platform.
///
/// The 2026-06-19 redesign removed the Semaphore provers (web/mobile/desktop);
/// all platforms now get the fenced stub until secret ballots move to
/// server-issued blind-signature credentials (Phase 4). The conditional-import
/// machinery (web vs native) is gone with the platform implementations.
ProofService createProofService() => createPlatformProofService();

/// Whether client-side proving is available. False everywhere now.
bool get proofServiceAvailable => platformProofServiceAvailable;
