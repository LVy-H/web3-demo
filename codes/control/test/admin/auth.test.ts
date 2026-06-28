import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { hashToken, bootstrapOperator } from "../../src/admin/auth";

let repos: ReturnType<typeof makeRepos>;
beforeEach(() => { const db = openDb(":memory:"); migrate(db); repos = makeRepos(db); });

describe("operator auth", () => {
  it("hashToken is stable sha256 hex", () => {
    expect(hashToken("abc")).toMatch(/^[0-9a-f]{64}$/);
    expect(hashToken("abc")).toBe(hashToken("abc"));
  });
  it("bootstrap mints once, stores only the hash", () => {
    const first = bootstrapOperator(repos);
    expect(first?.token).toMatch(/.{20,}/);
    expect(repos.operators.findByTokenHash(hashToken(first!.token))).not.toBeNull();
    expect(bootstrapOperator(repos)).toBeNull(); // idempotent
  });
});
