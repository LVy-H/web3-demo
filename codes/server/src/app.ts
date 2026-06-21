import express from "express";
import cors from "cors";
import type { Db, Repos } from "./db";
import type { ServerKey } from "./crypto";
import { convenerRouter } from "./routes/convener";
import { participantRouter } from "./routes/participant";
import { publicRouter } from "./routes/public";

/**
 * Per-route rate-limit window (§10). `windowMs` is the rolling window, `max` the
 * permitted requests per client IP within it.
 */
export interface RateLimitConfig {
  windowMs: number;
  max: number;
}

/** Tunable server policy (separate from wiring). */
export interface AppConfig {
  /**
   * Rate-limit for `POST /ballots` (§10). `undefined` → a sensible default
   * (60/min per IP); `null` → DISABLED (used by tests/e2e that cast fast).
   */
  ballotRateLimit?: RateLimitConfig | null;
}

/** The Phase-2 default ballot rate-limit: 60 casts/minute per client IP. */
export const DEFAULT_BALLOT_RATE_LIMIT: RateLimitConfig = {
  windowMs: 60_000,
  max: 60,
};

/**
 * Everything the HTTP layer needs, injected so tests are deterministic and the
 * bootstrap (index.ts) owns process-level concerns (env, listen, key dir).
 */
export interface AppDeps {
  db: Db;
  repos: Repos;
  serverKey: ServerKey;
  /** Monotone clock; injectable for deterministic tests. */
  now?: () => number;
  /** Tunable policy (rate-limit, …); defaults applied per field. */
  config?: AppConfig;
}

/**
 * Build the Express app WITHOUT listening, so tests (supertest) can import it
 * and the bootstrap (index.ts) can add app.listen separately.
 *
 * This is the Tessera self-hosted server (design 2026-06-19): the convener
 * lifecycle, the idempotent append-only ballot cast with signed receipts, and
 * the public read API are mounted here. Blind-sign issuer + RFC 6962 Merkle
 * checkpoints + the anchor adapter land in Phase 3.
 */
export function createApp(deps: AppDeps): express.Express {
  const now = deps.now ?? (() => Date.now());
  const app = express();

  // Trust the first proxy hop so client IPs are correct behind nginx/cloudflared.
  app.set("trust proxy", 1);
  app.use(cors());
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok" });
  });

  app.use(
    convenerRouter({ repos: deps.repos, serverKey: deps.serverKey, now }),
  );
  // Ballot rate-limit (§10): default 60/min per IP; `null` disables it.
  const ballotRateLimit =
    deps.config?.ballotRateLimit === undefined
      ? DEFAULT_BALLOT_RATE_LIMIT
      : deps.config.ballotRateLimit;

  app.use(
    participantRouter({
      db: deps.db,
      repos: deps.repos,
      serverKey: deps.serverKey,
      now,
      ballotRateLimit,
    }),
  );
  app.use(publicRouter({ repos: deps.repos, serverKey: deps.serverKey }));

  return app;
}
