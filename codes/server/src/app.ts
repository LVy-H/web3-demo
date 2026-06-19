import express from "express";
import cors from "cors";

/**
 * Build the Express app WITHOUT listening, so tests (supertest) can import it
 * and the bootstrap (index.ts) can add app.listen separately.
 *
 * This is the seed of the Tessera self-hosted server (design 2026-06-19):
 * the append-only ballot log, lifecycle, eligibility, blind-sign issuer,
 * checkpoints/anchor, and the public read API land here in Phases 2-3.
 */
export function createApp(): express.Express {
  const app = express();

  // Trust the first proxy hop so client IPs are correct behind nginx/cloudflared.
  app.set("trust proxy", 1);
  app.use(cors());
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok" });
  });

  return app;
}
