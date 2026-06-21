import Database from "better-sqlite3";
import { MIGRATIONS } from "./migrations";

export type { Migration } from "./migrations";
export {
  makeRepos,
  DuplicateBallotError,
} from "./repos";
export type {
  Repos,
  Account,
  AccountInput,
  AccountRepo,
  Decision,
  DecisionInput,
  DecisionListFilter,
  DecisionRepo,
  Ballot,
  BallotInput,
  BallotRepo,
  Receipt,
  ReceiptInput,
  ReceiptRepo,
  LifecycleEvent,
  LifecycleEventInput,
  LifecycleRepo,
  EligibilityRecord,
  EligibilityInput,
  EligibilityRepo,
  DecisionHead,
  HeadRepo,
  Checkpoint,
  CheckpointInput,
  CheckpointRepo,
} from "./repos";

/** The better-sqlite3 connection type, re-exported for callers' signatures. */
export type Db = Database.Database;

/**
 * Open (creating if absent) a SQLite database tuned for the single-writer,
 * durable, append-only discipline the Tessera server relies on (design §12.6):
 *   - journal_mode=WAL    → concurrent readers + one writer, crash-safe log
 *   - synchronous=FULL    → fsync on commit; survive power loss
 *   - busy_timeout=5000   → wait up to 5s rather than throwing SQLITE_BUSY
 *   - foreign_keys=ON     → enforce the REFERENCES in the schema
 */
export function openDb(path: string): Db {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = FULL");
  db.pragma("busy_timeout = 5000");
  db.pragma("foreign_keys = ON");
  return db;
}

/**
 * Apply any migrations not yet recorded, in `id` order, each in its own
 * transaction. Idempotent: re-running applies nothing and never duplicates a
 * `_migrations` row. The `_migrations` table is created on first run.
 */
export function migrate(db: Db): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id          INTEGER PRIMARY KEY,
      name        TEXT    NOT NULL,
      applied_at  INTEGER NOT NULL
    );
  `);

  const applied = new Set(
    (db.prepare(`SELECT id FROM _migrations`).all() as { id: number }[]).map(
      (r) => r.id,
    ),
  );

  const record = db.prepare(
    `INSERT INTO _migrations (id, name, applied_at) VALUES (?, ?, ?)`,
  );

  const ordered = [...MIGRATIONS].sort((a, b) => a.id - b.id);
  for (const m of ordered) {
    if (applied.has(m.id)) continue;
    const apply = db.transaction(() => {
      db.exec(m.sql);
      record.run(m.id, m.name, Date.now());
    });
    apply();
  }
}
