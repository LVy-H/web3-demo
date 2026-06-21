/**
 * Tessera server — anchor adapter (system-design §12.1, V5 trust levels).
 *
 * A pluggable `Anchor` takes a final `Checkpoint` and distributes (or doesn't)
 * its signed root, at one of three disclosed trust levels:
 *
 *  - **broadcast** (default, zero-wallet): the signed final root is distributed
 *    to voters/verifiers. Tamper-evident if any voter keeps it; equivocation only
 *    detectable by voters comparing. No host wallet → "one command" stays true.
 *  - **casual**: host-attested only — NO signed-root distribution. Branded
 *    "unverifiable / trust-the-host."
 *  - **chain**: the equivocation-resistant upgrade (post roots to a public L2).
 *    Here it is a STUB seam only: `anchor()` records `{status:'queued'}` and an
 *    actual `submit()` throws `ChainAnchorNotImplemented` (Phase-post-1.0). No
 *    real chain is implemented.
 *
 * Pure: depends only on the checkpoint types. No db / express / io / network.
 */
import type { Checkpoint } from "./checkpoint";

/** Distributable bundle for the zero-wallet broadcast anchor (carries the sig). */
export interface BroadcastBundle {
  mode: "broadcast";
  root: string;
  treeSize: number;
  /** The signed final root voters/verifiers keep (tamper-evident). */
  signedRoot: string;
}

/** Bundle for the casual anchor — deliberately omits any signed distribution. */
export interface CasualBundle {
  mode: "casual";
  root: string;
  treeSize: number;
}

/** Bundle for the (stubbed) chain anchor — recorded as queued, never submitted. */
export interface ChainBundle {
  mode: "chain";
  status: "queued";
}

export type AnchorBundle = BroadcastBundle | CasualBundle | ChainBundle;

export type AnchorMode = "broadcast" | "casual" | "chain";

/** The V5 trust/status level an anchor reports for the result page. */
export type AnchorStatus = "broadcast" | "casual" | "queued";

/**
 * Anchor adapter interface. `anchor()` produces the mode's distribution bundle;
 * `status()` reports the V5 trust level; `submit()` is the live-distribution
 * seam (only the chain adapter does real work there — and for now it throws).
 */
export interface Anchor {
  readonly mode: AnchorMode;
  /** Take a final checkpoint and produce its distribution bundle. */
  anchor(checkpoint: Checkpoint): AnchorBundle;
  /** The disclosed trust level / status for this anchor. */
  status(): AnchorStatus;
  /** Push the checkpoint to the anchor's backend (chain only; stubbed). */
  submit(checkpoint: Checkpoint): void;
}

/**
 * Typed error for the not-yet-implemented chain anchor (Phase-post-1.0). A
 * distinct class so callers can `instanceof`-discriminate the "upgrade not wired"
 * case from a genuine anchoring failure.
 */
export class ChainAnchorNotImplemented extends Error {
  constructor(
    message = "chain anchor is a post-1.0 stub: roots are queued but not submitted to any chain",
  ) {
    super(message);
    this.name = "ChainAnchorNotImplemented";
    // Preserve the prototype chain when targeting older runtimes.
    Object.setPrototypeOf(this, ChainAnchorNotImplemented.prototype);
  }
}

const broadcastAnchor: Anchor = {
  mode: "broadcast",
  anchor(checkpoint: Checkpoint): BroadcastBundle {
    return {
      mode: "broadcast",
      root: checkpoint.root,
      treeSize: checkpoint.treeSize,
      signedRoot: checkpoint.signedRoot,
    };
  },
  status: () => "broadcast",
  submit(checkpoint: Checkpoint): void {
    // Broadcast "submission" is just making the bundle available; nothing to
    // push to an external backend. Idempotent no-op.
    void checkpoint;
  },
};

const casualAnchor: Anchor = {
  mode: "casual",
  anchor(checkpoint: Checkpoint): CasualBundle {
    // Deliberately omit signedRoot — casual is host-attested only.
    return {
      mode: "casual",
      root: checkpoint.root,
      treeSize: checkpoint.treeSize,
    };
  },
  status: () => "casual",
  submit(checkpoint: Checkpoint): void {
    // No signed distribution to make. No-op.
    void checkpoint;
  },
};

const chainAnchor: Anchor = {
  mode: "chain",
  anchor(checkpoint: Checkpoint): ChainBundle {
    // Record intent only — the root is queued, never sent to a chain here.
    void checkpoint;
    return { mode: "chain", status: "queued" };
  },
  status: () => "queued",
  submit(checkpoint: Checkpoint): never {
    void checkpoint;
    throw new ChainAnchorNotImplemented();
  },
};

/**
 * Select an anchor adapter by mode. Defaults to the zero-wallet `broadcast`
 * anchor (system-design §12.1 default). Throws on an unsupported mode.
 */
export function anchorFor(mode: AnchorMode = "broadcast"): Anchor {
  switch (mode) {
    case "broadcast":
      return broadcastAnchor;
    case "casual":
      return casualAnchor;
    case "chain":
      return chainAnchor;
    default:
      throw new TypeError(`anchor: unsupported anchor mode "${String(mode)}"`);
  }
}
