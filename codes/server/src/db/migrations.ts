/**
 * Ordered, append-only schema migrations for the Tessera server.
 *
 * Rules (per the Phase-2 plan, Module A):
 *  - Migrations are numbered and append-only. NEVER edit a shipped migration's
 *    SQL; add a new higher-numbered entry instead. `migrate()` applies any not
 *    yet recorded in `_migrations`, in `id` order, each in its own transaction.
 *  - Phase-2 active tables only (design §9): accounts, decisions, ballots,
 *    receipts, lifecycle_events, eligibility_records, decision_head.
 *  - IDs/JSON are TEXT; timestamps are INTEGER epoch milliseconds.
 *  - `ballots` is APPEND-ONLY: BEFORE UPDATE/DELETE triggers RAISE(ABORT).
 *
 * Phase-3 tables (checkpoints — id 3; signing_keys + issued_credentials — id 4/5
 * for SECRET ballots) arrive as later, append-only numbered migrations.
 */
export interface Migration {
  /** Strictly increasing integer; defines apply order and dedup key. */
  readonly id: number;
  /** Human-readable label, stored for auditability. */
  readonly name: string;
  /** SQL applied in a single transaction. May contain multiple statements. */
  readonly sql: string;
}

export const MIGRATIONS: readonly Migration[] = [
  {
    id: 1,
    name: "phase2-core",
    sql: /* sql */ `
      CREATE TABLE accounts (
        id           TEXT    PRIMARY KEY,
        display_name TEXT    NOT NULL,
        token_hash   TEXT    NOT NULL UNIQUE,
        created_at   INTEGER NOT NULL
      );

      CREATE TABLE decisions (
        id               TEXT    PRIMARY KEY,
        convener_id      TEXT    NOT NULL REFERENCES accounts(id),
        title            TEXT    NOT NULL,
        options_json     TEXT    NOT NULL,
        method           TEXT    NOT NULL,
        eligibility_json TEXT    NOT NULL,
        visibility       TEXT    NOT NULL,
        ballot_mode      TEXT    NOT NULL,
        results_policy   TEXT    NOT NULL,
        rule_json        TEXT    NOT NULL,
        schedule_json    TEXT,
        anchor_mode      TEXT    NOT NULL,
        max_participants INTEGER,
        setup_commitment TEXT    NOT NULL,
        state            TEXT    NOT NULL,
        created_at       INTEGER NOT NULL
      );
      CREATE INDEX idx_decisions_convener ON decisions(convener_id);
      CREATE INDEX idx_decisions_state    ON decisions(state);

      CREATE TABLE ballots (
        id                TEXT    PRIMARY KEY,
        decision_id       TEXT    NOT NULL REFERENCES decisions(id),
        payload_json      TEXT    NOT NULL,
        credential_serial TEXT,
        idempotency_key   TEXT    NOT NULL,
        log_seq           INTEGER NOT NULL,
        prev_head         TEXT    NOT NULL,
        ballot_hash       TEXT    NOT NULL,
        created_at        INTEGER NOT NULL,
        UNIQUE(decision_id, idempotency_key)
      );
      CREATE INDEX idx_ballots_decision_seq ON ballots(decision_id, log_seq);

      -- ballots are APPEND-ONLY: forbid mutation/removal of committed rows.
      CREATE TRIGGER trg_ballots_no_update
        BEFORE UPDATE ON ballots
      BEGIN
        SELECT RAISE(ABORT, 'ballots are append-only');
      END;
      CREATE TRIGGER trg_ballots_no_delete
        BEFORE DELETE ON ballots
      BEGIN
        SELECT RAISE(ABORT, 'ballots are append-only');
      END;

      CREATE TABLE receipts (
        ballot_hash  TEXT    PRIMARY KEY,
        decision_id  TEXT    NOT NULL REFERENCES decisions(id),
        log_position INTEGER NOT NULL,
        running_root TEXT    NOT NULL,
        server_sig   TEXT    NOT NULL,
        created_at   INTEGER NOT NULL
      );
      CREATE INDEX idx_receipts_decision ON receipts(decision_id);

      CREATE TABLE lifecycle_events (
        id          TEXT    PRIMARY KEY,
        decision_id TEXT    NOT NULL REFERENCES decisions(id),
        transition  TEXT    NOT NULL,
        actor       TEXT    NOT NULL,
        ts          INTEGER NOT NULL,
        signed_sig  TEXT    NOT NULL
      );
      CREATE INDEX idx_lifecycle_decision ON lifecycle_events(decision_id, ts);

      CREATE TABLE eligibility_records (
        id                 TEXT    PRIMARY KEY,
        decision_id        TEXT    NOT NULL REFERENCES decisions(id),
        method             TEXT    NOT NULL,
        identifier_or_hash TEXT    NOT NULL,
        status             TEXT    NOT NULL,
        challengeable      INTEGER NOT NULL,
        used_counter       INTEGER NOT NULL DEFAULT 0,
        UNIQUE(decision_id, identifier_or_hash)
      );
      CREATE INDEX idx_eligibility_decision ON eligibility_records(decision_id);

      CREATE TABLE decision_head (
        decision_id TEXT    PRIMARY KEY REFERENCES decisions(id),
        head        TEXT    NOT NULL,
        leaf_count  INTEGER NOT NULL
      );
    `,
  },
  {
    id: 2,
    name: "lifecycle-closes-at",
    // Persist the 'extend' amendment's re-anchored close time so the cast path
    // and the startup reconcile can compute the EFFECTIVE close (latest extend's
    // closesAt, else the decision schedule) without re-deriving it from the
    // signed preimage (M2). Nullable: only 'extend' rows carry it.
    sql: /* sql */ `
      ALTER TABLE lifecycle_events ADD COLUMN closes_at INTEGER;
    `,
  },
  {
    id: 3,
    name: "phase3-checkpoints",
    // Phase-3 (§11 checkpoints / §12.1 anchor): the server signs the RFC 6962
    // Merkle root over the published ballotHash leaves and persists each signed
    // checkpoint here. The FINAL checkpoint (built on /publish) is the broadcast
    // anchor `/anchor` serves so a verifier can bind the served ballots to a
    // host-independent signed root (root-binding, §11 step 5).
    //
    // Append-only audit log: one row per built checkpoint, ordered by tree_size.
    // `signed_root` is the detached Ed25519 signature (base64) over
    // canonicalize({ root, treeSize, decisionId }) — the EXACT verifier preimage.
    sql: /* sql */ `
      CREATE TABLE checkpoints (
        id          TEXT    PRIMARY KEY,
        decision_id TEXT    NOT NULL REFERENCES decisions(id),
        root        TEXT    NOT NULL,
        tree_size   INTEGER NOT NULL,
        prev_root   TEXT,
        signed_root TEXT    NOT NULL,
        created_at  INTEGER NOT NULL
      );
      CREATE INDEX idx_checkpoints_decision ON checkpoints(decision_id, tree_size);

      -- checkpoints are an append-only audit trail: forbid mutation/removal.
      CREATE TRIGGER trg_checkpoints_no_update
        BEFORE UPDATE ON checkpoints
      BEGIN
        SELECT RAISE(ABORT, 'checkpoints are append-only');
      END;
      CREATE TRIGGER trg_checkpoints_no_delete
        BEFORE DELETE ON checkpoints
      BEGIN
        SELECT RAISE(ABORT, 'checkpoints are append-only');
      END;
    `,
  },
  {
    id: 4,
    name: "secret-signing-keys",
    // SECRET ballots (§12.2): one per-decision RFC 9474 RSABSSA-PSS issuer key.
    // `pub_key_hash` (= sha256hex(public_key_pem)) is folded into the decision's
    // setupCommitment and anchored before registration, so the host cannot swap
    // signing keys mid-decision (§6, §11.1). The PRIVATE key never leaves the
    // server: only `POST /register`'s blindSign touches it.
    //
    // PRIMARY KEY(decision_id): exactly one issuer per decision.
    sql: /* sql */ `
      CREATE TABLE signing_keys (
        decision_id     TEXT    PRIMARY KEY REFERENCES decisions(id),
        public_key_pem  TEXT    NOT NULL,
        private_key_pem TEXT    NOT NULL,
        pub_key_hash    TEXT    NOT NULL,
        created_at      INTEGER NOT NULL
      );
    `,
  },
  {
    id: 5,
    name: "secret-issued-credentials",
    // SECRET ballots issued-credential ledger (§6/§9 IssuedCredential, §11.2).
    // One append-only row per blind-signature issued at registration. It backs
    // the §6 "issued-count ≤ roster size" stuffing audit — a roster member can
    // dispute "the registered count is 47 but only 30 of us registered". It holds
    // NO link to the eventual ballot (the credential is blind), only that an
    // issuance happened for this decision and when.
    //
    // Append-only audit trail: forbid mutation/removal of recorded issuances.
    sql: /* sql */ `
      CREATE TABLE issued_credentials (
        id          TEXT    PRIMARY KEY,
        decision_id TEXT    NOT NULL REFERENCES decisions(id),
        issued_at   INTEGER NOT NULL
      );
      CREATE INDEX idx_issued_credentials_decision ON issued_credentials(decision_id);

      CREATE TRIGGER trg_issued_credentials_no_update
        BEFORE UPDATE ON issued_credentials
      BEGIN
        SELECT RAISE(ABORT, 'issued_credentials are append-only');
      END;
      CREATE TRIGGER trg_issued_credentials_no_delete
        BEFORE DELETE ON issued_credentials
      BEGIN
        SELECT RAISE(ABORT, 'issued_credentials are append-only');
      END;
    `,
  },
];
