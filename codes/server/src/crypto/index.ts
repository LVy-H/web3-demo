/**
 * Tessera server — crypto module (Phase 2).
 *
 * Canonical serialization + SHA-256, the §9 setupCommitment, the Ed25519 server
 * signing key, and the receipt hash-chain. Built only on `node:crypto`
 * primitives (no third-party crypto deps). Phase 3 adds the per-decision
 * RSABSSA-PSS blind-signature issuer (§12.2) and RFC 6962 Merkle checkpoints.
 */
export { canonicalize } from "./canonicalize";
export { sha256hex } from "./hash";
export { computeSetupCommitment, type SetupParts } from "./setupCommitment";
export { loadOrCreateServerKey, verifySig, type ServerKey } from "./serverKey";
export { chainNext, genesisHead } from "./chain";
