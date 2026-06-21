/**
 * Tessera server — independent verifier module (Phase 3, Module V).
 *
 * The differentiator: recompute the published result from public data alone and
 * bind it to the anchored Merkle root, so anyone can "check the result
 * themselves, without trusting the host" (system-design §11). Pure — reuses
 * `../crypto`, `../merkle`, `../tally`; no db/express/io. A CLI (`cli.ts`) runs
 * it over a bundle file/stdin.
 */
export {
  verifyDecision,
  recomputeBallotHash,
  signedRootPreimage,
  LEAF_DOMAIN,
  type VerifierBundle,
  type VerifierReport,
  type Check,
  type BundleBallot,
  type BundleAnchor,
  type BundleDecision,
} from "./verifyDecision";
