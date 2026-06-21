import { randomBytes } from "node:crypto";
import type { RequestHandler } from "express";
import type { Account, Db, Repos } from "../db";
import { sha256hex } from "../crypto";

/**
 * Tessera convener auth (system-design §9/§10).
 *
 * Bearer tokens gate all convener routes. We NEVER store a plaintext token:
 * only its SHA-256 hash lands in `accounts.token_hash`, and the plaintext is
 * surfaced to the caller exactly once (printed to logs on bootstrap, or
 * returned from `mintConvenerToken`). On a request we hash the presented
 * bearer and look it up, so a database leak does not yield usable tokens.
 */

/** Bytes of entropy in a generated token (256-bit). base64url → 43 chars. */
const TOKEN_BYTES = 32;

/** Generate a cryptographically-random, URL-safe bearer token. */
function generateToken(): string {
  return randomBytes(TOKEN_BYTES).toString("base64url");
}

/** SHA-256 (lowercase hex) of a bearer token — the value stored in the db. */
export function hashToken(token: string): string {
  return sha256hex(token);
}

/**
 * Whether any convener account exists yet, and the earliest one if so.
 *
 * The `AccountRepo` contract (src/db/repos.ts) deliberately exposes only
 * `create` / `get(id)` / `findByTokenHash(hash)` — no enumeration. Detecting
 * the first-run condition therefore needs a read-only probe against the open
 * connection, which is why `bootstrapAdmin` takes the `Db` handle the caller
 * already holds. This does NOT modify the db module; it only reads from it.
 */
function earliestAccount(db: Db): Account | null {
  const row = db
    .prepare(
      `SELECT id, display_name, token_hash, created_at
         FROM accounts
        ORDER BY created_at ASC, id ASC
        LIMIT 1`,
    )
    .get() as
    | { id: string; display_name: string; token_hash: string; created_at: number }
    | undefined;
  if (!row) return null;
  return {
    id: row.id,
    displayName: row.display_name,
    tokenHash: row.token_hash,
    createdAt: row.created_at,
  };
}

/**
 * Ensure a first-run admin account exists. Idempotent across restarts:
 *   - if NO accounts exist: mint a fresh random token, create the `admin`
 *     account storing only its hash, and return `{ token, account }` so the
 *     caller can print the plaintext to logs ONCE.
 *   - if an account already exists: return `{ token: null, account: <admin> }`
 *     where `<admin>` is the earliest-created account.
 *
 * Takes the open `Db` handle (alongside `repos`) purely for the read-only
 * "is the accounts table empty?" probe the repo interface does not expose.
 */
export function bootstrapAdmin(
  db: Db,
  repos: Repos,
): { token: string | null; account: Account } {
  const existing = earliestAccount(db);
  if (existing) return { token: null, account: existing };

  const token = generateToken();
  const account = repos.accounts.create({
    displayName: "admin",
    tokenHash: hashToken(token),
  });
  return { token, account };
}

/**
 * Mint a new convener account with a fresh random bearer token. Only the hash
 * is persisted; the plaintext token is returned once for out-of-band delivery
 * to the convener.
 */
export function mintConvenerToken(
  repos: Repos,
  displayName: string,
): { token: string; account: Account } {
  const token = generateToken();
  const account = repos.accounts.create({
    displayName,
    tokenHash: hashToken(token),
  });
  return { token, account };
}

/** Extract the raw bearer token from an `Authorization` header value. */
function parseBearer(header: string | undefined): string | null {
  if (!header) return null;
  const [scheme, ...rest] = header.split(" ");
  if (scheme.toLowerCase() !== "bearer") return null;
  const token = rest.join(" ").trim();
  return token.length > 0 ? token : null;
}

/**
 * Express middleware factory gating convener routes behind a bearer token.
 *
 *   - missing/non-Bearer Authorization header → 401 `AUTH_REQUIRED`
 *   - present but unknown/malformed token      → 401 `AUTH_INVALID`
 *   - valid token → attaches `req.account` and calls `next()`
 *
 * Error bodies follow the §10 stable error model: `{ error, code }`.
 */
export function requireConvener(repos: Repos): RequestHandler {
  return (req, res, next) => {
    const token = parseBearer(req.header("authorization") ?? undefined);
    if (!token) {
      res.status(401).json({ error: "unauthorized", code: "AUTH_REQUIRED" });
      return;
    }
    const account = repos.accounts.findByTokenHash(hashToken(token));
    if (!account) {
      res.status(401).json({ error: "unauthorized", code: "AUTH_INVALID" });
      return;
    }
    req.account = account;
    next();
  };
}
