import type { Decision as DecisionRow } from "../db";
import type {
  Method,
  BallotMode,
  ResultsPolicy,
  AnchorMode,
  Visibility,
  DecisionRule,
  Schedule,
  EligibilityPolicy,
} from "../domain";

/**
 * A `Decision` row carries its variable-shape config as JSON columns
 * (`optionsJson`, `ruleJson`, …). Route handlers need the parsed shapes, so this
 * one place inflates a row into the typed object the API + tally oracle consume.
 * Kept out of the db module deliberately — the persisted shape is JSON strings.
 */
export interface ParsedDecision {
  id: string;
  convenerId: string;
  title: string;
  options: string[];
  method: Method;
  ballotMode: BallotMode;
  resultsPolicy: ResultsPolicy;
  eligibility: EligibilityPolicy;
  rule: DecisionRule;
  schedule: Schedule;
  visibility: Visibility;
  anchorMode: AnchorMode;
  maxParticipants: number | null;
  setupCommitment: string;
  state: string;
  createdAt: number;
}

export function parseDecision(row: DecisionRow): ParsedDecision {
  return {
    id: row.id,
    convenerId: row.convenerId,
    title: row.title,
    options: JSON.parse(row.optionsJson) as string[],
    method: row.method as Method,
    ballotMode: row.ballotMode as BallotMode,
    resultsPolicy: row.resultsPolicy as ResultsPolicy,
    eligibility: JSON.parse(row.eligibilityJson) as EligibilityPolicy,
    rule: JSON.parse(row.ruleJson) as DecisionRule,
    schedule: (row.scheduleJson ? JSON.parse(row.scheduleJson) : {}) as Schedule,
    visibility: row.visibility as Visibility,
    anchorMode: row.anchorMode as AnchorMode,
    maxParticipants: row.maxParticipants,
    setupCommitment: row.setupCommitment,
    state: row.state,
    createdAt: row.createdAt,
  };
}
