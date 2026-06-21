import express from "express";
import cors from "cors";
import type { Db, Repos } from "./db";
import type { ServerKey } from "./crypto";
import { convenerRouter } from "./routes/convener";
import { participantRouter } from "./routes/participant";
import { publicRouter } from "./routes/public";

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
  app.use(
    participantRouter({
      db: deps.db,
      repos: deps.repos,
      serverKey: deps.serverKey,
      now,
    }),
  );
  app.use(publicRouter({ repos: deps.repos }));

  return app;
}
