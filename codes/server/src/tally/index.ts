/**
 * Tessera tally oracle — public API.
 *
 * Pure, dependency-free tally + verdict for the six decision methods, shared by
 * the Phase-2 server and replayed verbatim by the Phase-3 verifier. The ranked
 * (IRV) and quadratic algorithms are ports of `core_domain/lib/voting/`.
 */

export { tally, runIrv, creditsToVotes } from "./methods";
export { verdict } from "./verdict";

export type {
  Method,
  BallotPayload,
  Rule,
  Tally,
  Verdict,
  VerdictOutcome,
  IrvRound,
} from "./types";
