import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll } from "vitest";
import { createApp } from "../../src/app";
import { openDb, migrate, makeRepos, type Db, type Repos } from "../../src/db";
import { loadOrCreateServerKey, type ServerKey } from "../../src/crypto";
import { bootstrapAdmin } from "../../src/auth";
import type { Express } from "express";

export interface TestApp {
  app: Express;
  db: Db;
  repos: Repos;
  serverKey: ServerKey;
  adminToken: string;
  /** The (mutable) monotonic clock backing the app's injected `now()`. */
  now: () => number;
}

export interface TestAppOverrides {
  /** Override the deterministic clock; default is a fixed monotonic counter. */
  now?: () => number;
}

/**
 * Build a fully-wired in-memory Tessera app for supertest:
 *   - `:memory:` SQLite + migrations + repos
 *   - an Ed25519 server key in a throwaway tmp dir (cleaned up on suite teardown)
 *   - a deterministic monotonic clock (each call advances 1ms) unless overridden
 *   - a bootstrapped admin account whose plaintext token is returned
 */
export function makeTestApp(overrides: TestAppOverrides = {}): TestApp {
  const db = openDb(":memory:");
  migrate(db);
  const repos = makeRepos(db);

  const keyDir = mkdtempSync(join(tmpdir(), "tessera-test-key-"));
  const serverKey = loadOrCreateServerKey(keyDir);

  // Deterministic monotonic clock: a fixed base that advances by 1ms per read,
  // so timestamps are stable across runs yet strictly increasing within one.
  let tick = 1_700_000_000_000;
  const now = overrides.now ?? (() => tick++);

  const { token } = bootstrapAdmin(db, repos);
  if (!token) {
    throw new Error("bootstrapAdmin returned no token on a fresh db");
  }

  const app = createApp({ db, repos, serverKey, now });

  // Best-effort cleanup of the temp key dir + connection after the suite.
  afterAll(() => {
    try {
      db.close();
    } catch {
      /* already closed */
    }
    try {
      rmSync(keyDir, { recursive: true, force: true });
    } catch {
      /* nothing to clean */
    }
  });

  return { app, db, repos, serverKey, adminToken: token, now };
}
