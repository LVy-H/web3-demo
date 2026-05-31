import 'proof_service.dart';
// Web build pulls the js_interop implementation; every other target gets the
// native stub. Keeps dart:js_interop out of native compiles.
import 'proof_service_stub.dart'
    if (dart.library.js_interop) 'proof_service_web.dart';

/// Returns the right [ProofService] for the current platform: web → snarkjs via
/// js_interop; native → unsupported stub (until the native prover is scoped).
ProofService createProofService() => createPlatformProofService();
