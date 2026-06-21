import express from "express";
import request from "supertest";
import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate, makeRepos, type Db, type Repos } from "../../src/db";
import { sha256hex } from "../../src/crypto";
import {
  hashToken,
  bootstrapAdmin,
  mintConvenerToken,
  requireConvener,
} from "../../src/auth";

/** Fresh in-memory db + repos per test (no shared state across cases). */
function freshDb(): { db: Db; repos: Repos } {
  const db = openDb(":memory:");
  migrate(db);
  return { db, repos: makeRepos(db) };
}

/** A throwaway app exposing one convener-gated route that echoes req.account. */
function appWith(repos: Repos): express.Express {
  const app = express();
  app.use(express.json());
  app.get("/whoami", requireConvener(repos), (req, res) => {
    res.status(200).json({ account: req.account });
  });
  return app;
}

describe("hashToken", () => {
  it("is sha256hex of the token (deterministic)", () => {
    expect(hashToken("hello")).toBe(sha256hex("hello"));
    expect(hashToken("hello")).toBe(hashToken("hello"));
  });

  it("differs per token", () => {
    expect(hashToken("a")).not.toBe(hashToken("b"));
  });
});

describe("bootstrapAdmin", () => {
  it("creates an admin with a fresh token when no accounts exist", () => {
    const { db, repos } = freshDb();
    const { token, account } = bootstrapAdmin(db, repos);

    expect(token).toBeTypeOf("string");
    expect((token as string).length).toBeGreaterThanOrEqual(40);
    expect(account.displayName).toBe("admin");
    // Only the hash is stored; the stored hash matches hashToken(plaintext).
    expect(account.tokenHash).toBe(hashToken(token as string));
    // The account is retrievable by its token hash.
    expect(repos.accounts.findByTokenHash(account.tokenHash)?.id).toBe(
      account.id,
    );
  });

  it("is idempotent across restarts: second call returns token=null + same account", () => {
    const { db, repos } = freshDb();
    const first = bootstrapAdmin(db, repos);
    const second = bootstrapAdmin(db, repos);

    expect(second.token).toBeNull();
    expect(second.account.id).toBe(first.account.id);
    expect(second.account.tokenHash).toBe(first.account.tokenHash);
  });
});

describe("mintConvenerToken", () => {
  it("yields a working, distinct convener token; stores only the hash", () => {
    const { db, repos } = freshDb();
    bootstrapAdmin(db, repos);

    const a = mintConvenerToken(repos, "Alice");
    const b = mintConvenerToken(repos, "Bob");

    expect(a.token).not.toBe(b.token);
    expect(a.account.displayName).toBe("Alice");
    expect(b.account.displayName).toBe("Bob");
    expect(a.account.tokenHash).toBe(hashToken(a.token));
    expect(repos.accounts.findByTokenHash(hashToken(a.token))?.id).toBe(
      a.account.id,
    );
    expect(repos.accounts.findByTokenHash(hashToken(b.token))?.id).toBe(
      b.account.id,
    );
  });
});

describe("requireConvener middleware", () => {
  let repos: Repos;
  let adminToken: string;

  beforeEach(() => {
    const fresh = freshDb();
    repos = fresh.repos;
    adminToken = bootstrapAdmin(fresh.db, fresh.repos).token as string;
  });

  it("401 AUTH_REQUIRED when no Authorization header", async () => {
    const res = await request(appWith(repos)).get("/whoami");
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "unauthorized", code: "AUTH_REQUIRED" });
  });

  it("401 AUTH_REQUIRED when header lacks Bearer scheme", async () => {
    const res = await request(appWith(repos))
      .get("/whoami")
      .set("Authorization", adminToken); // no "Bearer " prefix
    expect(res.status).toBe(401);
    expect(res.body.code).toBe("AUTH_REQUIRED");
  });

  it("401 AUTH_INVALID for an unknown/malformed bearer token", async () => {
    const res = await request(appWith(repos))
      .get("/whoami")
      .set("Authorization", "Bearer not-a-real-token");
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "unauthorized", code: "AUTH_INVALID" });
  });

  it("200 and attaches req.account for a valid bootstrap token", async () => {
    const res = await request(appWith(repos))
      .get("/whoami")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.account.displayName).toBe("admin");
  });

  it("200 for a freshly minted convener token", async () => {
    const { token } = mintConvenerToken(repos, "Carol");
    const res = await request(appWith(repos))
      .get("/whoami")
      .set("Authorization", `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.account.displayName).toBe("Carol");
  });
});
