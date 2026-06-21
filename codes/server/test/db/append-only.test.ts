import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type Database from "better-sqlite3";
import { openDb, migrate, makeRepos } from "../../src/db";
import type { Repos } from "../../src/db";
import { tmpDbPath } from "./helpers";

/** Seed one account + decision + a single ballot row so we can attack it. */
function seedBallot(repos: Repos): { decisionId: string; ballotId: string } {
  const acc = repos.accounts.create({
    displayName: "Convener",
    tokenHash: "hash-aaa",
  });
  const dec = repos.decisions.insert({
    convenerId: acc.id,
    title: "Lunch?",
    optionsJson: JSON.stringify(["A", "B"]),
    method: "single",
    eligibilityJson: JSON.stringify({ mode: "open" }),
    visibility: "public",
    ballotMode: "open",
    resultsPolicy: "live",
    ruleJson: JSON.stringify({ threshold: { kind: "plurality" } }),
    scheduleJson: null,
    anchorMode: "casual",
    maxParticipants: null,
    setupCommitment: "sc-1",
    state: "open",
  });
  const ballot = repos.ballots.append({
    decisionId: dec.id,
    payloadJson: JSON.stringify({ choice: 0 }),
    credentialSerial: null,
    idempotencyKey: "k-1",
    logSeq: 1,
    prevHead: "genesis",
    ballotHash: "bh-1",
  });
  return { decisionId: dec.id, ballotId: ballot.id };
}

describe("ballots are append-only (BEFORE UPDATE/DELETE triggers)", () => {
  let db: Database.Database;
  let repos: Repos;
  let cleanup: () => void;
  let ballotId: string;

  beforeEach(() => {
    const t = tmpDbPath();
    cleanup = t.cleanup;
    db = openDb(t.path);
    migrate(db);
    repos = makeRepos(db);
    ballotId = seedBallot(repos).ballotId;
  });

  afterEach(() => {
    db.close();
    cleanup();
  });

  it("rejects UPDATE on a ballots row", () => {
    expect(() =>
      db
        .prepare(`UPDATE ballots SET payload_json = ? WHERE id = ?`)
        .run(JSON.stringify({ choice: 1 }), ballotId),
    ).toThrow(/append-only/);
  });

  it("rejects DELETE on a ballots row", () => {
    expect(() =>
      db.prepare(`DELETE FROM ballots WHERE id = ?`).run(ballotId),
    ).toThrow(/append-only/);
    // and the row survives
    const still = db
      .prepare(`SELECT COUNT(*) AS c FROM ballots WHERE id = ?`)
      .get(ballotId) as { c: number };
    expect(still.c).toBe(1);
  });
});
