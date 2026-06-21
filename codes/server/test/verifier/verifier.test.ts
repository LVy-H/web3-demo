import { describe, it, expect } from "vitest";
import { generateKeyPairSync, sign as edSign } from "node:crypto";

import {
  canonicalize,
  sha256hex,
  computeSetupCommitment,
} from "../../src/crypto";
import { merkleRoot } from "../../src/merkle";
import { tally, verdict, type BallotPayload, type Rule } from "../../src/tally";

import { verifyDecision, type VerifierBundle } from "../../src/verifier";

/**
 * These tests pin the §11 verification protocol against the SAME public recipes
 * the integration will make the server emit:
 *
 *   ballotHash = sha256hex('tessera:leaf:v1\n' + canonicalize(
 *                  { decisionId, logSeq, payload, serial: serial ?? null }))
 *   signedRoot = serverSign(canonicalize({ root, treeSize, decisionId }))
 *
 * A VALID bundle is built from scratch (crypto + merkle + an ephemeral Ed25519
 * key playing the server) so the tests assert the verifier accepts a faithfully
 * constructed bundle and then rejects exactly one check per tamper.
 */

const LEAF_DOMAIN = "tessera:leaf:v1\n";

// ── ephemeral "server" key ─────────────────────────────────────────────────
const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const serverPubKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();

function serverSign(msg: string): string {
  return edSign(null, Buffer.from(msg, "utf8"), privateKey).toString("base64");
}

interface RawBallot {
  logSeq: number;
  payload: BallotPayload;
  serial: string | null;
}

function ballotHashOf(decisionId: string, b: RawBallot): string {
  return sha256hex(
    LEAF_DOMAIN +
      canonicalize({
        decisionId,
        logSeq: b.logSeq,
        payload: b.payload,
        serial: b.serial ?? null,
      }),
  );
}

const DECISION_ID = "dec-abc-123";

const DECISION = {
  id: DECISION_ID,
  title: "Adopt the charter?",
  options: ["Yes", "No", "Abstain-option"],
  method: "single" as const,
  ballotMode: "secret" as const,
  resultsPolicy: "live" as const,
  rule: {
    threshold: { kind: "majority" as const },
    tieBreak: "declare" as const,
  } satisfies Rule,
  schedule: { opensAt: 1000, closesAt: 2000 },
  visibility: "listed" as const,
  anchorMode: "broadcast" as const,
  rosterCommitment: "roster-commitment-xyz",
  issuerPubKeyHash: "issuer-pubkey-hash-abc",
};

const RAW_BALLOTS: RawBallot[] = [
  { logSeq: 0, payload: { kind: "single", choice: 0 }, serial: "serial-0" },
  { logSeq: 1, payload: { kind: "single", choice: 0 }, serial: "serial-1" },
  { logSeq: 2, payload: { kind: "single", choice: 1 }, serial: "serial-2" },
  { logSeq: 3, payload: { kind: "single", choice: 0 }, serial: "serial-3" },
  { logSeq: 4, payload: { kind: "abstain" }, serial: "serial-4" },
];

/** Build a fully valid, internally-consistent bundle. */
function buildValidBundle(): VerifierBundle {
  const setupCommitment = computeSetupCommitment({
    options: DECISION.options,
    method: DECISION.method,
    rule: DECISION.rule,
    ballotMode: DECISION.ballotMode,
    resultsPolicy: DECISION.resultsPolicy,
    rosterCommitment: DECISION.rosterCommitment,
    issuerPubKeyHash: DECISION.issuerPubKeyHash,
    schedule: DECISION.schedule,
  });

  const ordered = [...RAW_BALLOTS].sort((a, b) => a.logSeq - b.logSeq);
  const ballots = ordered.map((b) => ({
    logSeq: b.logSeq,
    payload: b.payload,
    serial: b.serial,
    ballotHash: ballotHashOf(DECISION_ID, b),
  }));

  const root = merkleRoot(ballots.map((b) => b.ballotHash));
  const treeSize = ballots.length;
  const signedRoot = serverSign(
    canonicalize({ root, treeSize, decisionId: DECISION_ID }),
  );

  const payloads = ballots.map((b) => b.payload);
  const t = tally(DECISION.method, payloads, DECISION.options.length);
  const v = verdict(t, DECISION.rule, t.totalCast);

  return {
    decision: DECISION,
    setupCommitment,
    serverPubKeyPem,
    ballots,
    anchor: { root, treeSize, signedRoot },
    publishedResult: { tally: t, verdict: v },
  };
}

function checkByName(report: ReturnType<typeof verifyDecision>, name: string) {
  const c = report.checks.find((x) => x.name === name);
  expect(c, `expected a check named "${name}"`).toBeDefined();
  return c!;
}

const CHECK_NAMES = [
  "setup",
  "leaves",
  "root-binding",
  "contiguity",
  "no-double-vote",
  "tally-verdict",
];

describe("verifyDecision — valid bundle", () => {
  it("accepts a faithfully-constructed bundle: ok===true, every check passes", () => {
    const report = verifyDecision(buildValidBundle());
    expect(report.ok).toBe(true);
    expect(report.decisionId).toBe(DECISION_ID);
    for (const name of CHECK_NAMES) {
      expect(checkByName(report, name).ok, `check ${name}`).toBe(true);
    }
  });

  it("recomputes the correct tally + verdict", () => {
    const report = verifyDecision(buildValidBundle());
    // 3x Yes(0), 1x No(1), 1x abstain → majority of non-abstain cast (4): 3 > 2 → carried option 0
    expect(report.tally.optionScores).toEqual([3, 1, 0]);
    expect(report.tally.abstain).toBe(1);
    expect(report.tally.totalCast).toBe(5);
    expect(report.verdict.outcome).toBe("carried");
    expect(report.verdict.winner).toBe(0);
  });
});

describe("verifyDecision — one tamper per check fails exactly that check", () => {
  it("setup: altered setupCommitment", () => {
    const b = buildValidBundle();
    b.setupCommitment = "deadbeef".repeat(8);
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "setup").ok).toBe(false);
    // others unaffected
    expect(checkByName(report, "leaves").ok).toBe(true);
    expect(checkByName(report, "root-binding").ok).toBe(true);
  });

  it("leaves: a mutated ballot payload no longer matches its served ballotHash", () => {
    const b = buildValidBundle();
    // Flip a vote in the payload but keep the (now-stale) served ballotHash.
    b.ballots[0].payload = { kind: "single", choice: 1 };
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "leaves").ok).toBe(false);
    // setup still fine (it doesn't depend on ballots)
    expect(checkByName(report, "setup").ok).toBe(true);
  });

  it("root-binding: a dropped ballot makes merkleRoot != anchor.root", () => {
    const b = buildValidBundle();
    // Drop the last ballot but leave anchor.root/treeSize as committed.
    b.ballots = b.ballots.slice(0, -1);
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "root-binding").ok).toBe(false);
  });

  it("root-binding: a forged/wrong-key signedRoot fails the signature", () => {
    const b = buildValidBundle();
    const { privateKey: otherKey } = generateKeyPairSync("ed25519");
    b.anchor.signedRoot = edSign(
      null,
      Buffer.from(
        canonicalize({
          root: b.anchor.root,
          treeSize: b.anchor.treeSize,
          decisionId: DECISION_ID,
        }),
        "utf8",
      ),
      otherKey,
    ).toString("base64");
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "root-binding").ok).toBe(false);
  });

  it("contiguity: a logSeq gap fails", () => {
    const b = buildValidBundle();
    // Make seqs 0,1,2,3,5 (gap at 4) and re-derive a consistent root + sig so
    // ONLY contiguity trips.
    b.ballots[4].logSeq = 5;
    const reBallots = b.ballots.map((bl) => ({
      ...bl,
      ballotHash: ballotHashOf(DECISION_ID, {
        logSeq: bl.logSeq,
        payload: bl.payload,
        serial: bl.serial,
      }),
    }));
    b.ballots = reBallots;
    const root = merkleRoot(reBallots.map((x) => x.ballotHash));
    b.anchor.root = root;
    b.anchor.signedRoot = serverSign(
      canonicalize({ root, treeSize: b.anchor.treeSize, decisionId: DECISION_ID }),
    );
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "contiguity").ok).toBe(false);
    // leaves + root-binding stay green (we re-derived them)
    expect(checkByName(report, "leaves").ok).toBe(true);
    expect(checkByName(report, "root-binding").ok).toBe(true);
  });

  it("no-double-vote: a duplicate secret-mode serial fails", () => {
    const b = buildValidBundle();
    // Reuse serial-0 on ballot index 1; re-derive that leaf + root + sig so only
    // the double-vote check trips.
    b.ballots[1].serial = "serial-0";
    const reBallots = b.ballots.map((bl) => ({
      ...bl,
      ballotHash: ballotHashOf(DECISION_ID, {
        logSeq: bl.logSeq,
        payload: bl.payload,
        serial: bl.serial,
      }),
    }));
    b.ballots = reBallots;
    const root = merkleRoot(reBallots.map((x) => x.ballotHash));
    b.anchor.root = root;
    b.anchor.signedRoot = serverSign(
      canonicalize({ root, treeSize: b.anchor.treeSize, decisionId: DECISION_ID }),
    );
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "no-double-vote").ok).toBe(false);
    expect(checkByName(report, "leaves").ok).toBe(true);
    expect(checkByName(report, "root-binding").ok).toBe(true);
  });

  it("tally-verdict: a wrong publishedResult fails", () => {
    const b = buildValidBundle();
    b.publishedResult = {
      tally: { ...b.publishedResult!.tally, optionScores: [99, 0, 0] },
      verdict: b.publishedResult!.verdict,
    };
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "tally-verdict").ok).toBe(false);
    // The verifier's OWN recomputed tally is still the honest one.
    expect(report.tally.optionScores).toEqual([3, 1, 0]);
  });

  it("tally-verdict: a wrong published verdict fails", () => {
    const b = buildValidBundle();
    b.publishedResult = {
      tally: b.publishedResult!.tally,
      verdict: { outcome: "failed" },
    };
    const report = verifyDecision(b);
    expect(report.ok).toBe(false);
    expect(checkByName(report, "tally-verdict").ok).toBe(false);
  });
});

describe("verifyDecision — robustness", () => {
  it("never throws on a structurally broken bundle; turns it into failed checks", () => {
    const broken = {} as unknown as VerifierBundle;
    const report = verifyDecision(broken);
    expect(report.ok).toBe(false);
    // It still produces the full check list.
    for (const name of CHECK_NAMES) {
      expect(report.checks.some((c) => c.name === name)).toBe(true);
    }
  });

  it("open mode: duplicate serials are host-trusted (noted, not failed)", () => {
    const b = buildValidBundle();
    // Open mode → serials are null; no double-vote enforcement.
    const openBallots = RAW_BALLOTS.map((rb) => ({ ...rb, serial: null }));
    b.decision = { ...DECISION, ballotMode: "open" };
    b.setupCommitment = computeSetupCommitment({
      options: DECISION.options,
      method: DECISION.method,
      rule: DECISION.rule,
      ballotMode: "open",
      resultsPolicy: DECISION.resultsPolicy,
      rosterCommitment: DECISION.rosterCommitment,
      issuerPubKeyHash: DECISION.issuerPubKeyHash,
      schedule: DECISION.schedule,
    });
    b.ballots = openBallots.map((rb) => ({
      logSeq: rb.logSeq,
      payload: rb.payload,
      serial: rb.serial,
      ballotHash: ballotHashOf(DECISION_ID, rb),
    }));
    const root = merkleRoot(b.ballots.map((x) => x.ballotHash));
    b.anchor.root = root;
    b.anchor.treeSize = b.ballots.length;
    b.anchor.signedRoot = serverSign(
      canonicalize({ root, treeSize: b.anchor.treeSize, decisionId: DECISION_ID }),
    );
    const t = tally(DECISION.method, b.ballots.map((x) => x.payload), DECISION.options.length);
    b.publishedResult = { tally: t, verdict: verdict(t, DECISION.rule, t.totalCast) };
    const report = verifyDecision(b);
    const dv = checkByName(report, "no-double-vote");
    expect(dv.ok).toBe(true);
    expect(dv.detail.toLowerCase()).toContain("host-trusted");
    expect(report.ok).toBe(true);
  });
});
