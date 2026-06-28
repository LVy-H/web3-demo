// Tessera domain — §9 entities + the lifecycle / configuration unions.
//
// Design source of truth: docs/superpowers/specs/2026-06-19-tessera-system-design.md §9.
// This module is pure types + a couple of frozen value tuples; no I/O, no db.

// ---------------------------------------------------------------------------
// Configuration unions / enums (§7, §9)
// ---------------------------------------------------------------------------

/**
 * Decision lifecycle states.
 *
 * Open mode runs:   draft → open → closed → challenge → published.
 * Secret mode runs: draft → registration → open → closed → challenge → published
 *   — 'registration' is where blind-sig credentials are issued, and it CLOSES
 *   before voting opens (registration-before-voting, §6/§11.0): this breaks the
 *   issuance↔cast ordering a live host could otherwise correlate.
 * The 'challenge' step is optional (closed → published is legal).
 * Any pre-publish state can transition to the terminal 'cancelled'.
 */
export type DecisionState =
  | "draft"
  | "registration"
  | "open"
  | "closed"
  | "challenge"
  | "published"
  | "cancelled";

/** Voting / tally methods (must match the tally oracle, Module B). */
export type Method = "single" | "approval" | "ranked" | "quadratic" | "survey";

/** Whether ballots are on-record (open) or blind-credentialed (secret). */
export type BallotMode = "open" | "secret";

/** Whether the tally is hidden until close (sealed) or shown live. */
export type ResultsPolicy = "sealed" | "live";

/** Public-anchor trust level (§12.1), disclosed to verifiers (V5). */
export type AnchorMode = "casual" | "broadcast" | "chain";

/** How a participant proves they are allowed to vote (§3 P2). */
export type EligibilityMethod = "open" | "passcode" | "domain" | "invite";

/** Discovery visibility (§3 C3). */
export type Visibility = "listed" | "link-only";

/** Pass-threshold kind for the decision rule (§3 C-rules). */
export type ThresholdKind = "plurality" | "majority" | "supermajority";

/** Tie-break policy for the decision rule (§3 C-rules). */
export type TieBreak = "declare" | "runoff" | "casting" | "random-seed";

/** Frozen tuple of all lifecycle states — the iteration source of truth. */
export const DECISION_STATES = [
  "draft",
  "registration",
  "open",
  "closed",
  "challenge",
  "published",
  "cancelled",
] as const satisfies readonly DecisionState[];

// ---------------------------------------------------------------------------
// Canonical ballot payload union (MUST MATCH the tally module exactly).
// ---------------------------------------------------------------------------

export type BallotPayload =
  | { kind: "single"; choice: number }
  | { kind: "approval"; choices: number[] }
  | { kind: "ranked"; ranking: number[] }
  | { kind: "quadratic"; votes: number[] }
  | { kind: "survey"; choices: number[] }
  | { kind: "abstain" };

// ---------------------------------------------------------------------------
// Decision configuration sub-objects (§3 C-rules, §9)
// ---------------------------------------------------------------------------

export interface Threshold {
  kind: ThresholdKind;
  /** Required percentage for a 'supermajority' threshold (e.g. 66.7). */
  percent?: number;
}

export interface DecisionRule {
  threshold: Threshold;
  /** Minimum participation for the result to count; absence = no quorum. */
  quorum?: number;
  tieBreak: TieBreak;
}

export interface Schedule {
  /** Epoch-ms (or any monotone int) at which voting opens; absent = manual. */
  opensAt?: number;
  /** Epoch-ms at which voting closes; absent = manual close. */
  closesAt?: number;
}

/**
 * Eligibility policy. `method` is the discriminant; remaining fields depend on it
 * (passcode hash for 'passcode', allowed domain for 'domain', etc.). Kept open
 * (index signature) so the schema layer owns per-method shape validation.
 */
export interface EligibilityPolicy {
  method: EligibilityMethod;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// §9 entities
// ---------------------------------------------------------------------------

/** Convener account (§9 Account). */
export interface Account {
  id: string;
  displayName: string;
  /** Hashed auth credential — never the raw token. */
  authCredentialHash: string;
  createdAt: number;
}

/** A decision = one question per Decision (§9, open question #3 unresolved). */
export interface Decision {
  id: string;
  convener: string;
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
  /** H(canonical(setup parts)) — anchored before registration (§9). */
  setupCommitment: string;
  state: DecisionState;
  createdAt: number;
  /** Optional cap on participants (open mode trades stuffing for friction). */
  maxParticipants?: number;
}

/** An appended ballot (§9 Ballot). Append-only; payload validated by the oracle. */
export interface Ballot {
  decisionId: string;
  payload: BallotPayload;
  idempotencyKey: string;
  /** Position in the append-only log. */
  logSeq: number;
  /** Running head before this ballot (the hash-chain link). */
  prevHead: string;
  /** Domain-separated hash of the canonical ballot. */
  ballotHash: string;
  /** Open-mode credential serial (secret-mode blind sig is Phase 3). */
  serial?: string;
  /** Signed blind credential (Phase 3 secret mode). */
  sig?: string;
}

/** A self-contained, server-signed receipt over the running root (§9 Receipt). */
export interface Receipt {
  ballotHash: string;
  logPosition: number;
  /** The running hash-chain root this receipt commits to. */
  runningRoot: string;
  /** Server signature over (ballotHash ‖ logPosition ‖ runningRoot). */
  serverSig: string;
}

/** Per-invitee / per-credential eligibility state (§9 EligibilityRecord). */
export interface EligibilityRecord {
  decisionId: string;
  method: EligibilityMethod;
  /** Identifier or its hash (passcode hash, invite token, domain rule, ...). */
  identifier: string;
  status: "issued" | "used";
  /** Whether a roster member can publicly dispute this record (§6). */
  challengeable?: boolean;
}

/** Signed admin transition trail, folded into the checkpointed log (§9). */
export interface LifecycleEvent {
  decisionId: string;
  from: DecisionState;
  to: DecisionState;
  actor: string;
  timestamp: number;
  /** Server signature over the canonical transition (tamper-evident). */
  signature: string;
}

/** Anchor / checkpoint status (§9 Anchor). Phase 2 records but does not post. */
export type CheckpointStatus = "interim" | "final" | "anchored";

/** Interim/final root checkpoint — the unit that gets anchored (§9 Checkpoint). */
export interface Checkpoint {
  prevRoot: string;
  root: string;
  /** Inclusive [fromSeq, toSeq] of the log range this checkpoint covers. */
  seqRange: [number, number];
  /** Reference into the anchor (txHash / broadcast ref); absent until posted. */
  anchorRef?: string;
  status: CheckpointStatus;
}
