/**
 * Tessera server — Merkle log module (Phase 3).
 *
 * RFC 6962 (Certificate Transparency) binary Merkle tree over SHA-256 with
 * domain-separated leaf/node hashing. Provides the verifier's root-binding and
 * inclusion-proof foundation (system-design §11.5). Pure — only `node:crypto`.
 */
export {
  merkleRoot,
  inclusionProof,
  verifyInclusion,
  leafHash,
  type InclusionProof,
} from "./merkle";
