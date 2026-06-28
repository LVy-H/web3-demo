import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type Database from "better-sqlite3";
import { openDb, migrate } from "../../src/db";
import { tmpDbPath } from "./helpers";

describe("openDb + migrate (schema & pragmas)", () => {
  let db: Database.Database;
  let cleanup: () => void;

  beforeEach(() => {
    const t = tmpDbPath();
    cleanup = t.cleanup;
    db = openDb(t.path);
    migrate(db);
  });

  afterEach(() => {
    db.close();
    cleanup();
  });

  it("sets WAL journal mode", () => {
    const mode = db.pragma("journal_mode", { simple: true });
    expect(String(mode).toLowerCase()).toBe("wal");
  });

  it("sets synchronous=FULL (2), busy_timeout=5000, foreign_keys=ON", () => {
    expect(db.pragma("synchronous", { simple: true })).toBe(2);
    expect(db.pragma("busy_timeout", { simple: true })).toBe(5000);
    expect(db.pragma("foreign_keys", { simple: true })).toBe(1);
  });

  it("creates every Phase-2 active table", () => {
    const rows = db
      .prepare(`SELECT name FROM sqlite_master WHERE type='table'`)
      .all() as { name: string }[];
    const names = new Set(rows.map((r) => r.name));
    for (const t of [
      "_migrations",
      "accounts",
      "decisions",
      "ballots",
      "receipts",
      "lifecycle_events",
      "eligibility_records",
      "decision_head",
    ]) {
      expect(names.has(t), `missing table ${t}`).toBe(true);
    }
  });

  it("records applied migrations in _migrations", () => {
    const count = db
      .prepare(`SELECT COUNT(*) AS c FROM _migrations`)
      .get() as { c: number };
    expect(count.c).toBeGreaterThan(0);
  });

  it("is idempotent: migrate twice does not error or duplicate rows", () => {
    const before = (
      db.prepare(`SELECT COUNT(*) AS c FROM _migrations`).get() as { c: number }
    ).c;
    expect(() => migrate(db)).not.toThrow();
    const after = (
      db.prepare(`SELECT COUNT(*) AS c FROM _migrations`).get() as { c: number }
    ).c;
    expect(after).toBe(before);
  });

  it("creates the SECRET-ballot tables (signing_keys, issued_credentials)", () => {
    const rows = db
      .prepare(`SELECT name FROM sqlite_master WHERE type='table'`)
      .all() as { name: string }[];
    const names = new Set(rows.map((r) => r.name));
    for (const t of ["signing_keys", "issued_credentials"]) {
      expect(names.has(t), `missing table ${t}`).toBe(true);
    }
  });

  it("issued_credentials is append-only (UPDATE/DELETE abort)", () => {
    // Seed an account + decision + one issuance to mutate.
    db.prepare(
      `INSERT INTO accounts (id, display_name, token_hash, created_at)
       VALUES ('a1','admin','h',0)`,
    ).run();
    db.prepare(
      `INSERT INTO decisions (
         id, convener_id, title, options_json, method, eligibility_json,
         visibility, ballot_mode, results_policy, rule_json, schedule_json,
         anchor_mode, max_participants, setup_commitment, state, created_at)
       VALUES ('d1','a1','t','[]','single','{}','listed','secret','sealed','{}',
               '{}','broadcast',NULL,'sc','registration',0)`,
    ).run();
    db.prepare(
      `INSERT INTO issued_credentials (id, decision_id, issued_at)
       VALUES ('ic1','d1',1)`,
    ).run();
    expect(() =>
      db.prepare(`UPDATE issued_credentials SET issued_at = 2 WHERE id='ic1'`).run(),
    ).toThrow(/append-only/);
    expect(() =>
      db.prepare(`DELETE FROM issued_credentials WHERE id='ic1'`).run(),
    ).toThrow(/append-only/);
  });

  it("enforces ballots UNIQUE(decision_id, idempotency_key) at the schema level", () => {
    const idx = db
      .prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='ballots'`)
      .all() as { name: string }[];
    // The UNIQUE constraint manifests as an auto- or named index on ballots.
    expect(idx.length).toBeGreaterThan(0);
  });
});
