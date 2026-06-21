import type Database from "better-sqlite3";
import { randomUUID } from "node:crypto";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/**
 * Thrown by `BallotRepo.append` when a ballot with the same
 * (decision_id, idempotency_key) already exists. The route layer maps this to
 * the exactly-once retry path (return the existing receipt) rather than a 500.
 */
export class DuplicateBallotError extends Error {
  readonly decisionId: string;
  readonly idempotencyKey: string;
  constructor(decisionId: string, idempotencyKey: string) {
    super(
      `ballot already exists for decision ${decisionId} idempotencyKey ${idempotencyKey}`,
    );
    this.name = "DuplicateBallotError";
    this.decisionId = decisionId;
    this.idempotencyKey = idempotencyKey;
  }
}

/** better-sqlite3 tags UNIQUE violations with this code on the thrown error. */
function isUniqueConstraint(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    (err as { code?: string }).code === "SQLITE_CONSTRAINT_UNIQUE"
  );
}

// ---------------------------------------------------------------------------
// Entity types (camelCase application shape; columns are snake_case)
// ---------------------------------------------------------------------------

export interface Account {
  id: string;
  displayName: string;
  tokenHash: string;
  createdAt: number;
}
export interface AccountInput {
  displayName: string;
  tokenHash: string;
}

export interface Decision {
  id: string;
  convenerId: string;
  title: string;
  optionsJson: string;
  method: string;
  eligibilityJson: string;
  visibility: string;
  ballotMode: string;
  resultsPolicy: string;
  ruleJson: string;
  scheduleJson: string | null;
  anchorMode: string;
  maxParticipants: number | null;
  setupCommitment: string;
  state: string;
  createdAt: number;
}
export interface DecisionInput {
  convenerId: string;
  title: string;
  optionsJson: string;
  method: string;
  eligibilityJson: string;
  visibility: string;
  ballotMode: string;
  resultsPolicy: string;
  ruleJson: string;
  scheduleJson: string | null;
  anchorMode: string;
  maxParticipants: number | null;
  setupCommitment: string;
  state: string;
}
export interface DecisionListFilter {
  convenerId?: string;
  state?: string;
}

export interface Ballot {
  id: string;
  decisionId: string;
  payloadJson: string;
  credentialSerial: string | null;
  idempotencyKey: string;
  logSeq: number;
  prevHead: string;
  ballotHash: string;
  createdAt: number;
}
export interface BallotInput {
  decisionId: string;
  payloadJson: string;
  credentialSerial: string | null;
  idempotencyKey: string;
  logSeq: number;
  prevHead: string;
  ballotHash: string;
}

export interface Receipt {
  ballotHash: string;
  decisionId: string;
  logPosition: number;
  runningRoot: string;
  serverSig: string;
  createdAt: number;
}
export interface ReceiptInput {
  ballotHash: string;
  decisionId: string;
  logPosition: number;
  runningRoot: string;
  serverSig: string;
}

export interface LifecycleEvent {
  id: string;
  decisionId: string;
  transition: string;
  actor: string;
  ts: number;
  signedSig: string;
}
export interface LifecycleEventInput {
  decisionId: string;
  transition: string;
  actor: string;
  ts: number;
  signedSig: string;
}

export interface EligibilityRecord {
  id: string;
  decisionId: string;
  method: string;
  identifierOrHash: string;
  status: string;
  challengeable: boolean;
  usedCounter: number;
}
export interface EligibilityInput {
  decisionId: string;
  method: string;
  identifierOrHash: string;
  status: string;
  challengeable: boolean;
}

export interface DecisionHead {
  decisionId: string;
  head: string;
  leafCount: number;
}

// ---------------------------------------------------------------------------
// Row shapes (raw snake_case rows from sqlite) + mappers
// ---------------------------------------------------------------------------

interface AccountRow {
  id: string;
  display_name: string;
  token_hash: string;
  created_at: number;
}
const toAccount = (r: AccountRow): Account => ({
  id: r.id,
  displayName: r.display_name,
  tokenHash: r.token_hash,
  createdAt: r.created_at,
});

interface DecisionRow {
  id: string;
  convener_id: string;
  title: string;
  options_json: string;
  method: string;
  eligibility_json: string;
  visibility: string;
  ballot_mode: string;
  results_policy: string;
  rule_json: string;
  schedule_json: string | null;
  anchor_mode: string;
  max_participants: number | null;
  setup_commitment: string;
  state: string;
  created_at: number;
}
const toDecision = (r: DecisionRow): Decision => ({
  id: r.id,
  convenerId: r.convener_id,
  title: r.title,
  optionsJson: r.options_json,
  method: r.method,
  eligibilityJson: r.eligibility_json,
  visibility: r.visibility,
  ballotMode: r.ballot_mode,
  resultsPolicy: r.results_policy,
  ruleJson: r.rule_json,
  scheduleJson: r.schedule_json,
  anchorMode: r.anchor_mode,
  maxParticipants: r.max_participants,
  setupCommitment: r.setup_commitment,
  state: r.state,
  createdAt: r.created_at,
});

interface BallotRow {
  id: string;
  decision_id: string;
  payload_json: string;
  credential_serial: string | null;
  idempotency_key: string;
  log_seq: number;
  prev_head: string;
  ballot_hash: string;
  created_at: number;
}
const toBallot = (r: BallotRow): Ballot => ({
  id: r.id,
  decisionId: r.decision_id,
  payloadJson: r.payload_json,
  credentialSerial: r.credential_serial,
  idempotencyKey: r.idempotency_key,
  logSeq: r.log_seq,
  prevHead: r.prev_head,
  ballotHash: r.ballot_hash,
  createdAt: r.created_at,
});

interface ReceiptRow {
  ballot_hash: string;
  decision_id: string;
  log_position: number;
  running_root: string;
  server_sig: string;
  created_at: number;
}
const toReceipt = (r: ReceiptRow): Receipt => ({
  ballotHash: r.ballot_hash,
  decisionId: r.decision_id,
  logPosition: r.log_position,
  runningRoot: r.running_root,
  serverSig: r.server_sig,
  createdAt: r.created_at,
});

interface LifecycleRow {
  id: string;
  decision_id: string;
  transition: string;
  actor: string;
  ts: number;
  signed_sig: string;
}
const toLifecycle = (r: LifecycleRow): LifecycleEvent => ({
  id: r.id,
  decisionId: r.decision_id,
  transition: r.transition,
  actor: r.actor,
  ts: r.ts,
  signedSig: r.signed_sig,
});

interface EligibilityRow {
  id: string;
  decision_id: string;
  method: string;
  identifier_or_hash: string;
  status: string;
  challengeable: number;
  used_counter: number;
}
const toEligibility = (r: EligibilityRow): EligibilityRecord => ({
  id: r.id,
  decisionId: r.decision_id,
  method: r.method,
  identifierOrHash: r.identifier_or_hash,
  status: r.status,
  challengeable: r.challengeable !== 0,
  usedCounter: r.used_counter,
});

interface HeadRow {
  decision_id: string;
  head: string;
  leaf_count: number;
}
const toHead = (r: HeadRow): DecisionHead => ({
  decisionId: r.decision_id,
  head: r.head,
  leafCount: r.leaf_count,
});

// ---------------------------------------------------------------------------
// Repo interfaces
// ---------------------------------------------------------------------------

export interface AccountRepo {
  create(a: AccountInput): Account;
  get(id: string): Account | null;
  findByTokenHash(tokenHash: string): Account | null;
}

export interface DecisionRepo {
  insert(d: DecisionInput): Decision;
  get(id: string): Decision | null;
  setState(id: string, state: string, at: number): void;
  list(filter?: DecisionListFilter): Decision[];
}

export interface BallotRepo {
  /** Append a ballot; throws {@link DuplicateBallotError} on duplicate key. */
  append(b: BallotInput): Ballot;
  byDecision(decisionId: string, afterSeq?: number, limit?: number): Ballot[];
  count(decisionId: string): number;
  /** Current chain head (latest ballot_hash) for a decision, or genesis ''. */
  head(decisionId: string): string;
}

export interface ReceiptRepo {
  put(r: ReceiptInput): Receipt;
  byBallot(ballotHash: string): Receipt | null;
}

export interface LifecycleRepo {
  append(e: LifecycleEventInput): LifecycleEvent;
  byDecision(decisionId: string): LifecycleEvent[];
}

export interface EligibilityRepo {
  create(e: EligibilityInput): EligibilityRecord;
  find(decisionId: string, identifierOrHash: string): EligibilityRecord | null;
  /** Increment used_counter and flip status to 'used'. */
  markUsed(id: string): void;
}

export interface HeadRepo {
  get(decisionId: string): DecisionHead | null;
  set(decisionId: string, head: string, leafCount: number): void;
}

export interface Repos {
  accounts: AccountRepo;
  decisions: DecisionRepo;
  ballots: BallotRepo;
  receipts: ReceiptRepo;
  lifecycle: LifecycleRepo;
  eligibility: EligibilityRepo;
  head: HeadRepo;
}

// ---------------------------------------------------------------------------
// Factory: prepared statements bound once per connection
// ---------------------------------------------------------------------------

export function makeRepos(db: Database.Database): Repos {
  // accounts ---------------------------------------------------------------
  const accInsert = db.prepare(
    `INSERT INTO accounts (id, display_name, token_hash, created_at)
     VALUES (@id, @displayName, @tokenHash, @createdAt)`,
  );
  const accById = db.prepare(`SELECT * FROM accounts WHERE id = ?`);
  const accByToken = db.prepare(`SELECT * FROM accounts WHERE token_hash = ?`);

  const accounts: AccountRepo = {
    create(a) {
      const row: Account = {
        id: randomUUID(),
        displayName: a.displayName,
        tokenHash: a.tokenHash,
        createdAt: Date.now(),
      };
      accInsert.run(row);
      return row;
    },
    get(id) {
      const r = accById.get(id) as AccountRow | undefined;
      return r ? toAccount(r) : null;
    },
    findByTokenHash(tokenHash) {
      const r = accByToken.get(tokenHash) as AccountRow | undefined;
      return r ? toAccount(r) : null;
    },
  };

  // decisions --------------------------------------------------------------
  const decInsert = db.prepare(
    `INSERT INTO decisions (
        id, convener_id, title, options_json, method, eligibility_json,
        visibility, ballot_mode, results_policy, rule_json, schedule_json,
        anchor_mode, max_participants, setup_commitment, state, created_at)
     VALUES (
        @id, @convenerId, @title, @optionsJson, @method, @eligibilityJson,
        @visibility, @ballotMode, @resultsPolicy, @ruleJson, @scheduleJson,
        @anchorMode, @maxParticipants, @setupCommitment, @state, @createdAt)`,
  );
  const decById = db.prepare(`SELECT * FROM decisions WHERE id = ?`);
  const decSetState = db.prepare(
    `UPDATE decisions SET state = ? WHERE id = ?`,
  );
  const decAll = db.prepare(
    `SELECT * FROM decisions ORDER BY created_at ASC, id ASC`,
  );
  const decByConvener = db.prepare(
    `SELECT * FROM decisions WHERE convener_id = ? ORDER BY created_at ASC, id ASC`,
  );
  const decByState = db.prepare(
    `SELECT * FROM decisions WHERE state = ? ORDER BY created_at ASC, id ASC`,
  );
  const decByConvenerState = db.prepare(
    `SELECT * FROM decisions WHERE convener_id = ? AND state = ?
     ORDER BY created_at ASC, id ASC`,
  );

  const decisions: DecisionRepo = {
    insert(d) {
      const row: Decision = {
        id: randomUUID(),
        ...d,
        createdAt: Date.now(),
      };
      decInsert.run(row);
      return row;
    },
    get(id) {
      const r = decById.get(id) as DecisionRow | undefined;
      return r ? toDecision(r) : null;
    },
    setState(id, state, _at) {
      // `at` is recorded by the signed LifecycleEvent (LifecycleRepo); the
      // decision row carries only the current state.
      decSetState.run(state, id);
    },
    list(filter) {
      let rows: DecisionRow[];
      if (filter?.convenerId && filter.state) {
        rows = decByConvenerState.all(
          filter.convenerId,
          filter.state,
        ) as DecisionRow[];
      } else if (filter?.convenerId) {
        rows = decByConvener.all(filter.convenerId) as DecisionRow[];
      } else if (filter?.state) {
        rows = decByState.all(filter.state) as DecisionRow[];
      } else {
        rows = decAll.all() as DecisionRow[];
      }
      return rows.map(toDecision);
    },
  };

  // ballots ----------------------------------------------------------------
  const balInsert = db.prepare(
    `INSERT INTO ballots (
        id, decision_id, payload_json, credential_serial, idempotency_key,
        log_seq, prev_head, ballot_hash, created_at)
     VALUES (
        @id, @decisionId, @payloadJson, @credentialSerial, @idempotencyKey,
        @logSeq, @prevHead, @ballotHash, @createdAt)`,
  );
  const balByDecision = db.prepare(
    `SELECT * FROM ballots WHERE decision_id = ? AND log_seq > ?
     ORDER BY log_seq ASC`,
  );
  const balByDecisionLimited = db.prepare(
    `SELECT * FROM ballots WHERE decision_id = ? AND log_seq > ?
     ORDER BY log_seq ASC LIMIT ?`,
  );
  const balCount = db.prepare(
    `SELECT COUNT(*) AS c FROM ballots WHERE decision_id = ?`,
  );
  const balHead = db.prepare(
    `SELECT ballot_hash FROM ballots WHERE decision_id = ?
     ORDER BY log_seq DESC LIMIT 1`,
  );

  const ballots: BallotRepo = {
    append(b) {
      const row: Ballot = {
        id: randomUUID(),
        ...b,
        createdAt: Date.now(),
      };
      try {
        balInsert.run(row);
      } catch (err) {
        if (isUniqueConstraint(err)) {
          throw new DuplicateBallotError(b.decisionId, b.idempotencyKey);
        }
        throw err;
      }
      return row;
    },
    byDecision(decisionId, afterSeq = 0, limit) {
      const rows =
        limit === undefined
          ? (balByDecision.all(decisionId, afterSeq) as BallotRow[])
          : (balByDecisionLimited.all(
              decisionId,
              afterSeq,
              limit,
            ) as BallotRow[]);
      return rows.map(toBallot);
    },
    count(decisionId) {
      return (balCount.get(decisionId) as { c: number }).c;
    },
    head(decisionId) {
      const r = balHead.get(decisionId) as { ballot_hash: string } | undefined;
      return r ? r.ballot_hash : "";
    },
  };

  // receipts ---------------------------------------------------------------
  const recInsert = db.prepare(
    `INSERT INTO receipts (
        ballot_hash, decision_id, log_position, running_root, server_sig, created_at)
     VALUES (@ballotHash, @decisionId, @logPosition, @runningRoot, @serverSig, @createdAt)`,
  );
  const recByBallot = db.prepare(`SELECT * FROM receipts WHERE ballot_hash = ?`);

  const receipts: ReceiptRepo = {
    put(r) {
      const row: Receipt = { ...r, createdAt: Date.now() };
      recInsert.run(row);
      return row;
    },
    byBallot(ballotHash) {
      const r = recByBallot.get(ballotHash) as ReceiptRow | undefined;
      return r ? toReceipt(r) : null;
    },
  };

  // lifecycle --------------------------------------------------------------
  const lcInsert = db.prepare(
    `INSERT INTO lifecycle_events (id, decision_id, transition, actor, ts, signed_sig)
     VALUES (@id, @decisionId, @transition, @actor, @ts, @signedSig)`,
  );
  const lcByDecision = db.prepare(
    `SELECT * FROM lifecycle_events WHERE decision_id = ?
     ORDER BY ts ASC, rowid ASC`,
  );

  const lifecycle: LifecycleRepo = {
    append(e) {
      const row: LifecycleEvent = { id: randomUUID(), ...e };
      lcInsert.run(row);
      return row;
    },
    byDecision(decisionId) {
      const rows = lcByDecision.all(decisionId) as LifecycleRow[];
      return rows.map(toLifecycle);
    },
  };

  // eligibility ------------------------------------------------------------
  const elInsert = db.prepare(
    `INSERT INTO eligibility_records (
        id, decision_id, method, identifier_or_hash, status, challengeable, used_counter)
     VALUES (@id, @decisionId, @method, @identifierOrHash, @status, @challengeable, 0)`,
  );
  const elFind = db.prepare(
    `SELECT * FROM eligibility_records
     WHERE decision_id = ? AND identifier_or_hash = ?`,
  );
  const elMarkUsed = db.prepare(
    `UPDATE eligibility_records
     SET used_counter = used_counter + 1, status = 'used' WHERE id = ?`,
  );

  const eligibility: EligibilityRepo = {
    create(e) {
      const row = {
        id: randomUUID(),
        decisionId: e.decisionId,
        method: e.method,
        identifierOrHash: e.identifierOrHash,
        status: e.status,
        challengeable: e.challengeable ? 1 : 0,
      };
      elInsert.run(row);
      return {
        id: row.id,
        decisionId: e.decisionId,
        method: e.method,
        identifierOrHash: e.identifierOrHash,
        status: e.status,
        challengeable: e.challengeable,
        usedCounter: 0,
      };
    },
    find(decisionId, identifierOrHash) {
      const r = elFind.get(decisionId, identifierOrHash) as
        | EligibilityRow
        | undefined;
      return r ? toEligibility(r) : null;
    },
    markUsed(id) {
      elMarkUsed.run(id);
    },
  };

  // decision_head ----------------------------------------------------------
  const headGet = db.prepare(`SELECT * FROM decision_head WHERE decision_id = ?`);
  const headSet = db.prepare(
    `INSERT INTO decision_head (decision_id, head, leaf_count)
     VALUES (?, ?, ?)
     ON CONFLICT(decision_id) DO UPDATE SET head = excluded.head, leaf_count = excluded.leaf_count`,
  );

  const head: HeadRepo = {
    get(decisionId) {
      const r = headGet.get(decisionId) as HeadRow | undefined;
      return r ? toHead(r) : null;
    },
    set(decisionId, headHash, leafCount) {
      headSet.run(decisionId, headHash, leafCount);
    },
  };

  return { accounts, decisions, ballots, receipts, lifecycle, eligibility, head };
}
