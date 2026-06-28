/**
 * Tally oracle — public types (the I/O contract).
 *
 * This module is the SHARED tally oracle for Tessera. It is intentionally
 * pure and dependency-free: the Phase-3 verifier replays these exact
 * functions over the published ballot set to recompute the result + verdict,
 * so anything that lands here must be reproducible from data alone (no I/O,
 * no clock, no randomness beyond an explicit caller-supplied seed).
 *
 * The ballot-payload union below is THE canonical wire shape; the
 * `core_domain` Dart layer and the Phase-2 `src/domain` zod schemas mirror it
 * field-for-field.
 */

/** Supported decision methods. */
export type Method = "single" | "approval" | "ranked" | "quadratic" | "survey";

/**
 * Canonical per-ballot payload union (the I/O contract).
 *
 * Option indices are 0-based. `abstain` is a first-class ballot: it is counted
 * toward turnout (`totalCast`) and the `abstain` bucket, but contributes
 * nothing to option scoring.
 */
export type BallotPayload =
  | { kind: "single"; choice: number } // one option index
  | { kind: "approval"; choices: number[] } // multi-select, one point each
  | { kind: "ranked"; ranking: number[] } // ordered indices, most-preferred first
  | { kind: "quadratic"; votes: number[] } // votes[i] >= 0 cast for option i (cost Σvᵢ² ≤ QUADRATIC_CREDITS)
  | { kind: "survey"; choices: number[] } // multi-select aggregate (like approval)
  | { kind: "abstain" };

/**
 * One IRV round of the ranked tally trace (mirror of `IrvRound` in
 * `ranked_irv.dart`). Emitted for auditability so a verifier / UI can replay
 * the runoff round by round, not just trust the final winner.
 */
export interface IrvRound {
  /** Per-option continuing-vote counts THIS round (eliminated options read 0). */
  counts: number[];
  /** `C` — number of continuing (non-exhausted) ballots this round, re-derived each round. */
  continuingBallots: number;
  /** Option that won this round via strict majority (`2*votes > C`), else undefined. */
  winner?: number;
  /** Option eliminated this round (fewest votes; ties → lowest index), else undefined. */
  eliminated?: number;
}

/**
 * The result of tallying one decision.
 *
 * `optionScores[i]` is the per-option score under the method:
 *  - single   → first-choice count
 *  - approval → approval count
 *  - survey   → selection count
 *  - quadratic→ summed votes (payload carries the votes vector directly)
 *  - ranked   → round-1 first-preference count (full runoff is in `rounds`)
 */
export interface Tally {
  method: Method;
  /** Number of options the decision was tallied over. */
  optionCount: number;
  /** Per-option score (length === optionCount). */
  optionScores: number[];
  /** Count of abstain ballots (excluded from option scoring). */
  abstain: number;
  /** Every ballot received, abstain included — i.e. turnout. */
  totalCast: number;
  /** Ranked only: per-round IRV trace (empty array on degenerate input). */
  rounds?: IrvRound[];
  /** Ranked only: the IRV winner, or null on empty/degenerate input. */
  winner?: number | null;
}

/** The decision rule applied on top of a {@link Tally} to produce a {@link Verdict}. */
export interface Rule {
  threshold:
    | { kind: "plurality" }
    | { kind: "majority" }
    | { kind: "supermajority"; percent: number };
  /**
   * Optional turnout quorum. Checked FIRST, against the `denominator` passed to
   * {@link verdict}. `turnout < quorum` ⇒ `quorum-not-met`. Met is inclusive (>=).
   */
  quorum?: number;
  /** How a tie at the deciding position is resolved. */
  tieBreak: "declare" | "runoff" | "casting" | "random-seed";
  /** Public, pre-committed seed for the `random-seed` tie-break (deterministic). */
  seed?: string;
}

/** Verdict outcomes (the published result states one of these, §3 C-rules). */
export type VerdictOutcome = "carried" | "failed" | "tie" | "quorum-not-met";

/** The recomputable decision outcome (§11 step 4). */
export interface Verdict {
  outcome: VerdictOutcome;
  /** Winning option index when `carried`; undefined otherwise. */
  winner?: number;
  /** Options tied at the deciding position (for any tie outcome). */
  tiedOptions?: number[];
  /** `runoff` tie-break: a runoff is required. */
  runoff?: boolean;
  /** `casting` tie-break: the convener casting vote is required. */
  needsCastingVote?: boolean;
}
