/**
 * Verdict — turn a {@link Tally} + decision {@link Rule} into the published
 * outcome (§3 C-rules, §11 step 4): carried / failed / tie / quorum-not-met.
 *
 * Determinism is mandatory: the Phase-3 verifier replays this over the
 * published ballots and compares to `/results`. The only non-counting input is
 * the explicit, pre-committed `seed` for the `random-seed` tie-break.
 *
 * DENOMINATOR CHOICE (documented per the contract):
 *  - QUORUM is a turnout gate, checked FIRST against the decision's turnout
 *    (`tally.totalCast`, abstain included). `turnout < quorum ⇒ quorum-not-met`;
 *    met is inclusive (`turnout >= quorum`).
 *  - THRESHOLD (majority / supermajority %) is measured against the
 *    NON-ABSTAIN CAST base (`totalCast - abstain`), per §3 "majority = >50% of
 *    non-abstain cast". Abstentions are turnout but not part of the pass base.
 *  - The `denominator` parameter carries the convener's C-rule eligible-vs-cast
 *    base. In open mode the published ballot set IS the cast set, so the
 *    verifier passes the cast count and it coincides with the non-abstain base
 *    once abstains are removed. It is accepted (and may be used by callers that
 *    measure the threshold against eligibility) but the Phase-2 pass base is the
 *    non-abstain cast derived from the tally, which is what the verifier can
 *    reproduce from published ballots alone.
 */

import type { Rule, Tally, Verdict } from "./types";

/**
 * Find the option(s) with the maximum score. Returns the winning index plus the
 * full set of options tied at that maximum (length > 1 ⇒ a tie at the top).
 */
function topOptions(scores: number[]): { top: number; max: number; tied: number[] } {
  let max = -1;
  for (const s of scores) if (s > max) max = s;
  const tied: number[] = [];
  for (let i = 0; i < scores.length; i++) if (scores[i] === max) tied.push(i);
  return { top: tied.length > 0 ? tied[0] : -1, max, tied };
}

/**
 * Deterministic FNV-1a 32-bit hash of the seed, used to pick among tied options
 * for the `random-seed` tie-break. Pure and reproducible from the seed alone.
 */
function seededPick(seed: string, tied: number[]): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  const idx = (h >>> 0) % tied.length;
  return tied[idx];
}

/** Resolve a tie among `tied` per the rule's tie-break; returns a Verdict. */
function resolveTie(tied: number[], rule: Rule): Verdict {
  switch (rule.tieBreak) {
    case "runoff":
      return { outcome: "tie", runoff: true, tiedOptions: tied };
    case "casting":
      return { outcome: "tie", needsCastingVote: true, tiedOptions: tied };
    case "random-seed": {
      const seed = rule.seed ?? "";
      return { outcome: "carried", winner: seededPick(seed, tied), tiedOptions: tied };
    }
    case "declare":
    default:
      return { outcome: "tie", tiedOptions: tied };
  }
}

/**
 * Compute the published verdict.
 *
 * @param t           the tally to evaluate.
 * @param rule        the decision rule (threshold / quorum / tie-break).
 * @param denominator the convener's C-rule eligible-vs-cast base (see header).
 */
export function verdict(t: Tally, rule: Rule, denominator: number): Verdict {
  // Turnout is intrinsic — every ballot received, abstain included. It can never
  // exceed the eligible/cast `denominator` the convener supplied, so clamp to it
  // (the published cast set IS the turnout in open mode, where denominator == cast).
  const turnout = Number.isFinite(denominator)
    ? Math.min(t.totalCast, denominator)
    : t.totalCast;

  // ── Quorum gate (checked FIRST, against turnout) ───────────────────────────
  if (rule.quorum !== undefined && turnout < rule.quorum) {
    return { outcome: "quorum-not-met" };
  }

  // Threshold base = the NON-ABSTAIN CAST (§3 "majority = >50% of non-abstain
  // cast"); the figure the verifier reproduces from the published ballots.
  // `denominator` is the eligibility context (used by the quorum clamp above and
  // reserved for Phase-3 eligible-base rules); see the file header.
  const nonAbstainCast = t.totalCast - t.abstain;
  const base = nonAbstainCast;

  // For ranked the deciding candidate is the IRV winner, not raw top score.
  if (t.method === "ranked") {
    return rankedVerdict(t, rule, base, nonAbstainCast);
  }

  // No effective ballots → nothing can carry / tie.
  if (nonAbstainCast <= 0) {
    return { outcome: "failed" };
  }

  const { top, max, tied } = topOptions(t.optionScores);

  // A tie at the deciding position (two+ options share the top score) means no
  // single option can win outright — the position is contested. Resolve per the
  // tie-break for EVERY threshold kind. (At a tie no option clears a strict
  // majority anyway, and supermajority winners must be unique.)
  if (max > 0 && tied.length > 1) {
    return resolveTie(tied, rule);
  }

  // Unique leader: carries iff it clears the rule's bar.
  if (max > 0 && passesThreshold(rule, max, base)) {
    return { outcome: "carried", winner: top };
  }
  return { outcome: "failed" };
}

/** True iff the leading score clears the rule's threshold over `base`. */
function passesThreshold(rule: Rule, max: number, base: number): boolean {
  switch (rule.threshold.kind) {
    case "plurality":
      // Any positive leading score is a plurality; ties handled by caller.
      return max > 0;
    case "majority":
      // Strict majority: > 50% of the non-abstain base (2*max > base).
      return 2 * max > base;
    case "supermajority": {
      // Inclusive at the boundary: max/base >= percent/100  ⇔  max*100 >= percent*base.
      // H1: fail LOUD on an ill-formed rule. This oracle is replayed by the
      // Phase-3 verifier on arbitrary data; a missing/non-finite percent must
      // throw, not compute max*100 >= NaN (always false) and silently report a
      // unanimous vote as 'failed'. The schema enforces percent at create time.
      const percent = rule.threshold.percent;
      if (typeof percent !== "number" || !Number.isFinite(percent)) {
        throw new Error("supermajority rule requires a finite percent");
      }
      return max * 100 >= percent * base;
    }
  }
}

/**
 * Verdict for ranked: the IRV winner must clear the threshold over `base`.
 * `nonAbstainCast` guards the degenerate no-effective-ballots case.
 */
function rankedVerdict(t: Tally, rule: Rule, base: number, nonAbstainCast: number): Verdict {
  if (nonAbstainCast <= 0 || base <= 0 || t.winner === null || t.winner === undefined) {
    return { outcome: "failed" };
  }
  const winnerScore = lastRoundScore(t, t.winner);
  if (passesThreshold(rule, winnerScore, base)) {
    return { outcome: "carried", winner: t.winner };
  }
  return { outcome: "failed" };
}

/**
 * The IRV winner's final-round continuing-vote count, evaluated against the
 * final round's continuing-ballot base — the figure the threshold (e.g.
 * majority) is judged on. Falls back to the round-1 first-preference count.
 */
function lastRoundScore(t: Tally, winner: number): number {
  if (t.rounds && t.rounds.length > 0) {
    const last = t.rounds[t.rounds.length - 1];
    return last.counts[winner] ?? 0;
  }
  return t.optionScores[winner] ?? 0;
}
