import { createHash, randomBytes } from "node:crypto";
import type { RequestHandler } from "express";
import type { makeRepos } from "../registry/repos";

type Repos = ReturnType<typeof makeRepos>;
export function hashToken(t: string): string { return createHash("sha256").update(t).digest("hex"); }

export function bootstrapOperator(repos: Repos): { token: string } | null {
  if (repos.operators.count() > 0) return null;
  const token = randomBytes(32).toString("base64url");
  repos.operators.create(hashToken(token));
  return { token };
}

export function requireOperator(repos: Repos): RequestHandler {
  return (req, res, next) => {
    const h = req.header("authorization") ?? "";
    const m = /^Bearer (.+)$/.exec(h);
    if (!m || !repos.operators.findByTokenHash(hashToken(m[1]))) {
      res.status(401).json({ error: "unauthorized" }); return;
    }
    next();
  };
}
