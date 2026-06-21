// Tessera decision lifecycle — the state machine (§9).
//
// Legal transitions (open mode; 'registration' is Phase-3 secret-mode only):
//   draft     → open
//   open      → closed
//   closed    → challenge
//   challenge → published
//   closed    → published                 (challenge optional)
//   {draft, open, closed, challenge} → cancelled
//
// NOTE: 'extend' is an AMENDMENT, not a state transition. Extending an open
// decision keeps the state 'open' — it appends a signed lifecycle event (the
// re-anchored close time) and never calls assertTransition. open → open is
// therefore NOT a legal edge here. (Treating it as a self-transition let a 2nd
// POST /open reset the running hash-chain head to genesis/leafCount-0 after
// ballots existed, forking the §11.5 root binding — finding C1.)
//
// Everything else is illegal — especially anything OUT of a terminal state
// ('published' | 'cancelled'), and lifecycle skips (e.g. draft → closed).

import type { DecisionState } from "./types";

/**
 * Adjacency: for each state, the set of states it may transition INTO.
 * Terminal states ('published', 'cancelled') map to the empty set.
 */
const TRANSITIONS: Readonly<Record<DecisionState, ReadonlySet<DecisionState>>> = {
  draft: new Set<DecisionState>(["open", "cancelled"]),
  // 'extend' is an amendment, not a transition: open does NOT map to open.
  open: new Set<DecisionState>(["closed", "cancelled"]),
  closed: new Set<DecisionState>(["challenge", "published", "cancelled"]),
  challenge: new Set<DecisionState>(["published", "cancelled"]),
  published: new Set<DecisionState>(),
  cancelled: new Set<DecisionState>(),
};

/** True iff `from → to` is a legal lifecycle transition. */
export function canTransition(from: DecisionState, to: DecisionState): boolean {
  return TRANSITIONS[from]?.has(to) ?? false;
}

/** Thrown by {@link assertTransition} on an illegal lifecycle transition. */
export class IllegalTransitionError extends Error {
  readonly from: DecisionState;
  readonly to: DecisionState;

  constructor(from: DecisionState, to: DecisionState) {
    super(`Illegal decision lifecycle transition: ${from} → ${to}`);
    this.name = "IllegalTransitionError";
    this.from = from;
    this.to = to;
    // Restore prototype chain for instanceof across transpile targets.
    Object.setPrototypeOf(this, IllegalTransitionError.prototype);
  }
}

/** Throws {@link IllegalTransitionError} unless `from → to` is legal. */
export function assertTransition(from: DecisionState, to: DecisionState): void {
  if (!canTransition(from, to)) {
    throw new IllegalTransitionError(from, to);
  }
}
