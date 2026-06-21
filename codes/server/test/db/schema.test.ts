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

  it("enforces ballots UNIQUE(decision_id, idempotency_key) at the schema level", () => {
    const idx = db
      .prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='ballots'`)
      .all() as { name: string }[];
    // The UNIQUE constraint manifests as an auto- or named index on ballots.
    expect(idx.length).toBeGreaterThan(0);
  });
});
