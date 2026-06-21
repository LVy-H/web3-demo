/**
 * Tessera server — checkpoint builder (system-design §11 checkpoints).
 *
 * A checkpoint is the unit that gets anchored: the RFC 6962 Merkle root over the
 * published ballotHash leaves (in logSeq order), its tree size, the carried
 * previous root, and the server's Ed25519 signature over the canonical
 * signed-root payload.
 *
 * The **signed-root payload is the load-bearing contract** with the verifier:
 *
 *     signedRoot = sign( canonicalize({ root, treeSize, decisionId }) )
 *
 * The independent verifier recomputes that exact canonical string and checks the
 * signature against the anchored per-decision server pubkey (§11 step 5). Both
 * sides MUST agree on these three fields and nothing else; do not add/remove keys
 * here without changing the verifier in lockstep.
 *
 * Pure: depends only on the Phase-2 `crypto` (canonicalize) and Phase-3 `merkle`
 * (merkleRoot) modules. No db / express / io.
 */
import { merkleRoot } from "../merkle";
import { canonicalize } from "../crypto";

/** A built (and signed) checkpoint over the Merkle log. */
export interface Checkpoint {
  /** The decision this checkpoint belongs to (bound into the signed payload). */
  decisionId: string;
  /** RFC 6962 Merkle root over the ballotHash leaves, lowercase hex. */
  root: string;
  /** Number of leaves committed (the CT tree size). */
  treeSize: number;
  /** Root of the prior checkpoint in the chain, or null for the first. */
  prevRoot: string | null;
  /** Detached Ed25519 signature (base64) over the canonical signed-root payload. */
  signedRoot: string;
  /** Lifecycle status of the checkpoint itself ("built" once signed). */
  status: "built";
}

export interface BuildCheckpointOpts {
  decisionId: string;
  /** ballotHash leaves (whole-byte hex), in logSeq order. */
  leaves: string[];
  /** Prior checkpoint root, or null for the first checkpoint. */
  prevRoot: string | null;
  /** Server signing function (e.g. ServerKey.sign): utf8(msg) -> base64 sig. */
  sign: (msg: string) => string;
}

/**
 * The EXACT canonical payload the server signs and the verifier recomputes.
 * Centralised so `buildCheckpoint` and `verifyCheckpointSig` can never drift.
 */
export function signedRootPayload(parts: {
  root: string;
  treeSize: number;
  decisionId: string;
}): string {
  return canonicalize({
    root: parts.root,
    treeSize: parts.treeSize,
    decisionId: parts.decisionId,
  });
}

/**
 * Build a signed checkpoint over `leaves`. Computes the RFC 6962 root, signs
 * `canonicalize({ root, treeSize, decisionId })`, and returns the checkpoint.
 */
export function buildCheckpoint(opts: BuildCheckpointOpts): Checkpoint {
  const { decisionId, leaves, prevRoot, sign } = opts;
  const root = merkleRoot(leaves);
  const treeSize = leaves.length;
  const signedRoot = sign(signedRootPayload({ root, treeSize, decisionId }));
  return { decisionId, root, treeSize, prevRoot, signedRoot, status: "built" };
}
