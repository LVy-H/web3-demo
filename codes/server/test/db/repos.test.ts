import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type Database from "better-sqlite3";
import {
  openDb,
  migrate,
  makeRepos,
  DuplicateBallotError,
  DuplicateSerialError,
} from "../../src/db";
import type { Repos } from "../../src/db";
import { tmpDbPath } from "./helpers";

function newAccount(repos: Repos, token = "hash-1") {
  return repos.accounts.create({ displayName: "Convener", tokenHash: token });
}

function newDecision(repos: Repos, convenerId: string) {
  return repos.decisions.insert({
    convenerId,
    title: "Pick a venue",
    optionsJson: JSON.stringify(["X", "Y", "Z"]),
    method: "ranked",
    eligibilityJson: JSON.stringify({ mode: "passcode" }),
    visibility: "public",
    ballotMode: "open",
    resultsPolicy: "sealed",
    ruleJson: JSON.stringify({ threshold: { kind: "majority" }, quorum: 3 }),
    scheduleJson: JSON.stringify({ closeAt: 1750000000000 }),
    anchorMode: "broadcast-head",
    maxParticipants: 100,
    setupCommitment: "commit-abc",
    state: "draft",
  });
}

describe("repos round-trip", () => {
  let db: Database.Database;
  let repos: Repos;
  let cleanup: () => void;

  beforeEach(() => {
    const t = tmpDbPath();
    cleanup = t.cleanup;
    db = openDb(t.path);
    migrate(db);
    repos = makeRepos(db);
  });

  afterEach(() => {
    db.close();
    cleanup();
  });

  it("accounts: create + findByTokenHash + get", () => {
    const a = newAccount(repos, "tok-hash");
    expect(a.id).toBeTruthy();
    expect(a.createdAt).toBeGreaterThan(0);
    const found = repos.accounts.findByTokenHash("tok-hash");
    expect(found?.id).toBe(a.id);
    expect(repos.accounts.findByTokenHash("nope")).toBeNull();
    expect(repos.accounts.get(a.id)?.displayName).toBe("Convener");
  });

  it("decisions: insert + get + setState + list", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    expect(d.state).toBe("draft");
    const got = repos.decisions.get(d.id);
    expect(got?.title).toBe("Pick a venue");
    expect(got?.method).toBe("ranked");
    expect(got?.maxParticipants).toBe(100);
    expect(got?.anchorMode).toBe("broadcast-head");

    repos.decisions.setState(d.id, "open", 1750000001000);
    expect(repos.decisions.get(d.id)?.state).toBe("open");

    const list = repos.decisions.list();
    expect(list.find((x) => x.id === d.id)).toBeTruthy();
    const byConvener = repos.decisions.list({ convenerId: a.id });
    expect(byConvener.every((x) => x.convenerId === a.id)).toBe(true);
  });

  it("ballots: append + byDecision + count + head", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);

    const b1 = repos.ballots.append({
      decisionId: d.id,
      payloadJson: JSON.stringify({ ranking: [0, 1, 2] }),
      credentialSerial: null,
      idempotencyKey: "key-1",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "hash-b1",
    });
    const b2 = repos.ballots.append({
      decisionId: d.id,
      payloadJson: JSON.stringify({ ranking: [2, 1, 0] }),
      credentialSerial: null,
      idempotencyKey: "key-2",
      logSeq: 2,
      prevHead: "hash-b1",
      ballotHash: "hash-b2",
    });
    expect(b1.id).not.toBe(b2.id);
    expect(repos.ballots.count(d.id)).toBe(2);

    const all = repos.ballots.byDecision(d.id);
    expect(all.map((b) => b.ballotHash)).toEqual(["hash-b1", "hash-b2"]);

    const afterFirst = repos.ballots.byDecision(d.id, 1);
    expect(afterFirst.map((b) => b.ballotHash)).toEqual(["hash-b2"]);

    const limited = repos.ballots.byDecision(d.id, 0, 1);
    expect(limited).toHaveLength(1);
    expect(limited[0].ballotHash).toBe("hash-b1");
  });

  it("ballots: duplicate (decision_id, idempotency_key) throws DuplicateBallotError", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.ballots.append({
      decisionId: d.id,
      payloadJson: "{}",
      credentialSerial: null,
      idempotencyKey: "dup",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "h1",
    });
    let caught: unknown;
    try {
      repos.ballots.append({
        decisionId: d.id,
        payloadJson: "{}",
        credentialSerial: null,
        idempotencyKey: "dup",
        logSeq: 2,
        prevHead: "h1",
        ballotHash: "h2",
      });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(DuplicateBallotError);
    expect((caught as DuplicateBallotError).idempotencyKey).toBe("dup");
    // count unchanged
    expect(repos.ballots.count(d.id)).toBe(1);
  });

  it("ballots: duplicate (decision_id, credential_serial) throws DuplicateSerialError", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.ballots.append({
      decisionId: d.id,
      payloadJson: "{}",
      credentialSerial: "serial-x",
      idempotencyKey: "k1",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "h1",
    });
    let caught: unknown;
    try {
      // Same serial, DIFFERENT idempotencyKey → only the serial UNIQUE fires,
      // so this must surface as DuplicateSerialError, not DuplicateBallotError.
      repos.ballots.append({
        decisionId: d.id,
        payloadJson: "{}",
        credentialSerial: "serial-x",
        idempotencyKey: "k2",
        logSeq: 2,
        prevHead: "h1",
        ballotHash: "h2",
      });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(DuplicateSerialError);
    expect((caught as DuplicateSerialError).credentialSerial).toBe("serial-x");
    // count unchanged — the double-vote INSERT aborted.
    expect(repos.ballots.count(d.id)).toBe(1);
  });

  it("ballots: NULL credential_serial (open ballots) never collide on the serial index", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.ballots.append({
      decisionId: d.id,
      payloadJson: "{}",
      credentialSerial: null,
      idempotencyKey: "o1",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "n1",
    });
    // A second open ballot (serial NULL) is allowed: the partial index excludes
    // NULLs, so the open-ballot model (multiple ballots via idempotencyKey) holds.
    expect(() =>
      repos.ballots.append({
        decisionId: d.id,
        payloadJson: "{}",
        credentialSerial: null,
        idempotencyKey: "o2",
        logSeq: 2,
        prevHead: "n1",
        ballotHash: "n2",
      }),
    ).not.toThrow();
    expect(repos.ballots.count(d.id)).toBe(2);
  });

  it("ballots: same idempotency_key across different decisions is allowed", () => {
    const a = newAccount(repos);
    const d1 = newDecision(repos, a.id);
    const d2 = newDecision(repos, a.id);
    repos.ballots.append({
      decisionId: d1.id,
      payloadJson: "{}",
      credentialSerial: null,
      idempotencyKey: "shared",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "x1",
    });
    expect(() =>
      repos.ballots.append({
        decisionId: d2.id,
        payloadJson: "{}",
        credentialSerial: null,
        idempotencyKey: "shared",
        logSeq: 1,
        prevHead: "genesis",
        ballotHash: "x2",
      }),
    ).not.toThrow();
  });

  it("receipts: put + byBallot", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.ballots.append({
      decisionId: d.id,
      payloadJson: "{}",
      credentialSerial: null,
      idempotencyKey: "k",
      logSeq: 1,
      prevHead: "genesis",
      ballotHash: "bh",
    });
    const r = repos.receipts.put({
      ballotHash: "bh",
      decisionId: d.id,
      logPosition: 1,
      runningRoot: "root-1",
      serverSig: "sig-1",
    });
    expect(r.ballotHash).toBe("bh");
    const got = repos.receipts.byBallot("bh");
    expect(got?.runningRoot).toBe("root-1");
    expect(got?.serverSig).toBe("sig-1");
    expect(repos.receipts.byBallot("missing")).toBeNull();
  });

  it("lifecycle: append + byDecision (chronological)", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.lifecycle.append({
      decisionId: d.id,
      transition: "open",
      actor: a.id,
      ts: 1750000000000,
      signedSig: "sig-open",
    });
    repos.lifecycle.append({
      decisionId: d.id,
      transition: "close",
      actor: a.id,
      ts: 1750000005000,
      signedSig: "sig-close",
    });
    const events = repos.lifecycle.byDecision(d.id);
    expect(events.map((e) => e.transition)).toEqual(["open", "close"]);
    expect(events[0].signedSig).toBe("sig-open");
  });

  it("eligibility: create + find + markUsed counter", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    const rec = repos.eligibility.create({
      decisionId: d.id,
      method: "passcode",
      identifierOrHash: "passhash-1",
      status: "issued",
      challengeable: true,
    });
    expect(rec.usedCounter).toBe(0);
    const found = repos.eligibility.find(d.id, "passhash-1");
    expect(found?.id).toBe(rec.id);

    repos.eligibility.markUsed(rec.id);
    const after = repos.eligibility.find(d.id, "passhash-1");
    expect(after?.usedCounter).toBe(1);
    expect(after?.status).toBe("used");
  });

  it("head: upsert + get (running root)", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    expect(repos.head.get(d.id)).toBeNull();
    repos.head.set(d.id, "head-1", 1);
    expect(repos.head.get(d.id)).toEqual({
      decisionId: d.id,
      head: "head-1",
      leafCount: 1,
    });
    repos.head.set(d.id, "head-2", 2);
    expect(repos.head.get(d.id)?.head).toBe("head-2");
    expect(repos.head.get(d.id)?.leafCount).toBe(2);
  });

  it("head: refuses to LOWER an existing leafCount (C1 append-only guard)", () => {
    const a = newAccount(repos);
    const d = newDecision(repos, a.id);
    repos.head.set(d.id, "head-3", 3);
    // A re-open that tries to reset the chain to genesis/leafCount-0 must throw,
    // never silently fork the §11.5 root binding.
    expect(() => repos.head.set(d.id, "", 0)).toThrow();
    // Same leafCount (idempotent re-write) is allowed; higher advances.
    expect(() => repos.head.set(d.id, "head-3", 3)).not.toThrow();
    repos.head.set(d.id, "head-4", 4);
    expect(repos.head.get(d.id)?.leafCount).toBe(4);
  });
});
