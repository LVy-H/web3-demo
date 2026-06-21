// Tessera domain — public API (entities + lifecycle state machine + zod schemas).
//
// Downstream layers (auth, routes) import from here, never from sibling modules
// directly.

// Entities + configuration unions + the canonical BallotPayload type.
export type {
  Account,
  Decision,
  Ballot,
  Receipt,
  LifecycleEvent,
  EligibilityRecord,
  Checkpoint,
  CheckpointStatus,
  DecisionState,
  Method,
  BallotMode,
  ResultsPolicy,
  AnchorMode,
  EligibilityMethod,
  Visibility,
  ThresholdKind,
  TieBreak,
  Threshold,
  DecisionRule,
  Schedule,
  EligibilityPolicy,
  BallotPayload,
} from "./types";

export { DECISION_STATES } from "./types";

// Lifecycle state machine.
export {
  canTransition,
  assertTransition,
  IllegalTransitionError,
} from "./lifecycle";

// Zod schemas.
export {
  DecisionCreateSchema,
  ballotPayloadSchema,
  type DecisionCreateInput,
} from "./schemas";
