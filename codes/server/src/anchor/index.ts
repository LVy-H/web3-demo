/**
 * Tessera server — checkpoint + anchor module (Phase 3, Module A).
 *
 * Signs the Merkle-log roots and distributes them at one of three V5 trust
 * levels (broadcast / casual / chain), so a verifier can bind the published
 * ballots to a host-independent signed root (system-design §11 checkpoints,
 * §12.1 anchor). Built over the existing `merkle` and `crypto` modules.
 *
 * The load-bearing contract is the signed-root payload:
 *     signedRoot = sign(canonicalize({ root, treeSize, decisionId }))
 * (see `signedRootPayload` — the verifier recomputes the same string).
 */
export {
  buildCheckpoint,
  signedRootPayload,
  type Checkpoint,
  type BuildCheckpointOpts,
} from "./checkpoint";

export { verifyCheckpointSig } from "./verify";

export {
  anchorFor,
  ChainAnchorNotImplemented,
  type Anchor,
  type AnchorMode,
  type AnchorStatus,
  type AnchorBundle,
  type BroadcastBundle,
  type CasualBundle,
  type ChainBundle,
} from "./anchor";
