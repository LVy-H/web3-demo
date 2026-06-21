/**
 * The six tally methods.
 *
 * Algorithms for `ranked` and `quadratic` are direct ports of the canonical
 * Dart sources (`core_domain/lib/voting/ranked_irv.dart` and
 * `quadratic_alloc.dart`) and must match their results bit-for-bit.
 */

import type { BallotPayload, IrvRound, Method, Tally } from "./types";

function inRange(option: number, optionCount: number): boolean {
  return Number.isInteger(option) && option >= 0 && option < optionCount;
}

/**
 * Run the canonical off-chain IRV rule over decoded rankings (each an ordered
 * list of option indices, most-preferred first).
 *
 * Direct port of `runIrv` in `ranked_irv.dart` — THE pinned, verifier-replayed
 * rule:
 *   1. Each round, every non-exhausted ballot counts for its highest-ranked
 *      not-yet-eliminated candidate; a ballot whose every ranked candidate is
 *      eliminated is exhausted and drops out of the count.
 *   2. `C` = continuing (non-exhausted) ballots THIS round — re-derived each round.
 *   3. WIN iff some candidate has `2*votes > C` (strict majority; exactly-half
 *      never wins). Win-check runs BEFORE elimination, including round 1.
 *   4. Else eliminate the fewest-vote candidate; tie-break = lowest option index.
 *   5. Terminate when one continuing candidate remains, or a strict majority hits.
 */
export function runIrv(
  ballots: number[][],
  optionCount: number,
): { winner: number | null; rounds: IrvRound[] } {
  const rounds: IrvRound[] = [];
  if (optionCount <= 0 || ballots.length === 0) {
    return { winner: null, rounds };
  }

  const continuing = new Set<number>();
  for (let i = 0; i < optionCount; i++) continuing.add(i);
  const eliminated = new Set<number>();

  // Bounded: at most optionCount-1 eliminations before one option remains.
  for (;;) {
    // Step 1 & 2: recompute per-option counts + C from scratch every round.
    const counts = new Array<number>(optionCount).fill(0);
    let continuingBallots = 0; // C
    for (const ballot of ballots) {
      let choice: number | undefined;
      for (const option of ballot) {
        // Guard against malformed decoded ballots; valid input is unaffected.
        if (!inRange(option, optionCount)) continue;
        if (!eliminated.has(option)) {
          choice = option;
          break;
        }
      }
      if (choice === undefined) continue; // exhausted — not counted in C
      counts[choice]++;
      continuingBallots++;
    }

    // Step 3: strict-majority win check BEFORE any elimination (never `>=`).
    for (const option of continuing) {
      if (2 * counts[option] > continuingBallots) {
        rounds.push({ counts, continuingBallots, winner: option });
        return { winner: option, rounds };
      }
    }

    // Step 5 (terminal): one continuing candidate remains ⇒ winner. Also
    // rescues the degenerate C===0 case (every ballot exhausted).
    if (continuing.size === 1) {
      const option = continuing.values().next().value as number;
      rounds.push({ counts, continuingBallots, winner: option });
      return { winner: option, rounds };
    }

    // Step 4: eliminate the fewest; tie-break = lowest option index. Iterate the
    // continuing set in ascending index order so the first option to reach the
    // minimum wins the tie, and a strictly-smaller count later supersedes it.
    let loser: number | undefined;
    let fewest = 0;
    const order = [...continuing].sort((a, b) => a - b);
    for (const option of order) {
      const v = counts[option];
      if (loser === undefined || v < fewest || (v === fewest && option < loser)) {
        loser = option;
        fewest = v;
      }
    }
    eliminated.add(loser as number);
    continuing.delete(loser as number);
    rounds.push({ counts, continuingBallots, eliminated: loser });
  }
}

/** The uniform quadratic vote-credit budget (mirror of `quadratic_alloc.dart` CREDITS). */
export const QUADRATIC_CREDITS = 100;

/**
 * Quadratic cost of a votes allocation: `Σ vᵢ²` — the mirror of `creditsSpent` in
 * `quadratic_alloc.dart`. A quadratic ballot carries the **votes** vector directly
 * (`votes[i]` = votes cast for option `i`); the tally sums those votes. A ballot is
 * valid iff `creditsSpent(votes) <= QUADRATIC_CREDITS` — the cast-time validity check
 * (and the figure the Phase-3 verifier reproduces from the published ballots).
 */
export function creditsSpent(votes: number[]): number {
  let sum = 0;
  for (const v of votes) sum += v * v;
  return sum;
}

/** Tally a decision under `method` over `ballots` for `optionCount` options. */
export function tally(
  method: Method,
  ballots: BallotPayload[],
  optionCount: number,
): Tally {
  const optionScores = new Array<number>(Math.max(0, optionCount)).fill(0);
  let abstain = 0;
  const totalCast = ballots.length;

  // Ranked is special: collect rankings, then replay the IRV rule.
  if (method === "ranked") {
    const rankings: number[][] = [];
    for (const b of ballots) {
      if (b.kind === "abstain") {
        abstain++;
        continue;
      }
      if (b.kind === "ranked") {
        rankings.push(b.ranking);
        // optionScores expose round-1 first-preference counts for display.
        for (const option of b.ranking) {
          if (inRange(option, optionCount)) {
            optionScores[option]++;
            break;
          }
        }
      }
    }
    const { winner, rounds } = runIrv(rankings, optionCount);
    return { method, optionCount, optionScores, abstain, totalCast, rounds, winner };
  }

  for (const b of ballots) {
    switch (b.kind) {
      case "abstain":
        abstain++;
        break;
      case "single":
        if (inRange(b.choice, optionCount)) optionScores[b.choice]++;
        break;
      case "approval":
      case "survey": {
        // Multi-select aggregate: one point per distinct in-range option.
        const seen = new Set<number>();
        for (const option of b.choices) {
          if (inRange(option, optionCount) && !seen.has(option)) {
            seen.add(option);
            optionScores[option]++;
          }
        }
        break;
      }
      case "quadratic": {
        // Payload carries the votes vector directly; sum votes per in-range option.
        for (let i = 0; i < Math.min(b.votes.length, optionCount); i++) {
          const v = b.votes[i];
          if (Number.isFinite(v) && v > 0) optionScores[i] += v;
        }
        break;
      }
      case "ranked":
        // Unreachable: ranked handled above. A ranked payload reaching here
        // (method mismatch) is ignored in scoring but still counted as cast.
        break;
    }
  }

  return { method, optionCount, optionScores, abstain, totalCast };
}
