import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll } from "vitest";
import { createApp, type AppConfig } from "../../src/app";
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
  /**
   * Server config (e.g. ballot rate-limit). DEFAULT: the /ballots rate-limit is
   * DISABLED for tests so the existing suite + e2e can cast many ballots fast
   * without tripping the limiter. Pass a `ballotRateLimit` to test enforcement.
   */
  config?: AppConfig;
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

  // Default config DISABLES the ballot rate-limit (ballotRateLimit: null) so the
  // existing tests + e2e cast ballots in tight loops without 429s. Override via
  // `config` to exercise the limiter.
  const config: AppConfig = overrides.config ?? { ballotRateLimit: null };
  const app = createApp({ db, repos, serverKey, now, config });

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
