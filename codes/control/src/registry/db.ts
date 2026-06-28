import Database from "better-sqlite3";
import { MIGRATIONS } from "./schema";
export function openDb(path: string): Database.Database {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  return db;
}
export function migrate(db: Database.Database): void {
  db.exec(`CREATE TABLE IF NOT EXISTS _migrations (id INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)`);
  const done = new Set<number>(
    (db.prepare(`SELECT id FROM _migrations`).all() as { id: number }[]).map((r) => r.id),
  );
  for (const m of MIGRATIONS) {
    if (done.has(m.id)) continue;
    db.transaction(() => {
      db.exec(m.sql.replace(/CREATE TABLE _migrations[^;]+;/, ""));
      db.prepare(`INSERT INTO _migrations (id, applied_at) VALUES (?, ?)`).run(m.id, Date.now());
    })();
  }
}
