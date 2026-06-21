import request from "supertest";
import { describe, it, expect } from "vitest";
import { makeTestApp } from "../helpers/app";
import { canonicalize, sha256hex } from "../../src/crypto";
import { merkleRoot } from "../../src/merkle";
import {
  verifyDecision,
  type VerifierBundle,
  type Check,
} from "../../src/verifier";

/**
 * §11 verifiable-open-ballot flow, end-to-end:
 *   create → open → cast×3 (one idempotent retry) → close → publish,
 * then recompute the RFC 6962 Merkle root over the served public leaves and
 * assert it equals the server's published /root, that /anchor broadcasts the
 * signed final root, and that GET /verify/:id reports ok with all six §11 checks
 * passing. A tamper test then mutates a served ballot and asserts verify fails.
 */
describe("e2e: verifiable open-ballot decision flow", () => {
  // The PUBLIC leaf recipe the server emits and the verifier recomputes (open
  // mode: serial = null; the idempotencyKey is NOT in the leaf).
  const leafOf = (decisionId: string, logSeq: number, payload: unknown) =>
    sha256hex(
      "tessera:leaf:v1\n" +
        canonicalize({ decisionId, logSeq, payload, serial: null }),
    );

  const createBody = {
    title: "Adopt the proposal?",
    options: ["Yes", "No"],
    method: "single",
    ballotMode: "open",
    resultsPolicy: "live",
    eligibility: { method: "open" },
    rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
    schedule: {},
    visibility: "listed",
    anchorMode: "broadcast",
  };

  it("create→open→cast→close→publish binds /root, /anchor and /verify to the recomputed Merkle root", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);

    // ── create (convener) ────────────────────────────────────────────────────
    const createRes = await auth(request(app).post("/decisions").send(createBody));
    expect(createRes.status).toBe(201);
    expect(createRes.body.state).toBe("draft");
    expect(typeof createRes.body.setupCommitment).toBe("string");
    const id: string = createRes.body.id;

    // ── open ─────────────────────────────────────────────────────────────────
    const openRes = await auth(request(app).post(`/decisions/${id}/open`));
    expect(openRes.status).toBe(200);
    expect(openRes.body.state).toBe("open");

    // ── cast 3 ballots: 2× option 0, 1× option 1 ─────────────────────────────
    const casts = [
      { payload: { kind: "single", choice: 0 }, idempotencyKey: "k-a" },
      { payload: { kind: "single", choice: 0 }, idempotencyKey: "k-b" },
      { payload: { kind: "single", choice: 1 }, idempotencyKey: "k-c" },
    ];
    const receipts: Array<{ ballotHash: string; logPosition: number; runningRoot: string }> = [];
    for (let i = 0; i < casts.length; i++) {
      const c = casts[i];
      const res = await request(app)
        .post("/ballots")
        .send({ decisionId: id, payload: c.payload, idempotencyKey: c.idempotencyKey });
      expect(res.status).toBe(201);
      // The receipt's ballotHash IS the public leaf at this logSeq.
      expect(res.body.receipt.ballotHash).toBe(leafOf(id, i, c.payload));
      expect(res.body.receipt.logPosition).toBe(i);
      receipts.push(res.body.receipt);
    }

    // ── idempotent retry of the first ballot returns the SAME receipt ─────────
    const retry = await request(app)
      .post("/ballots")
      .send({ decisionId: id, payload: casts[0].payload, idempotencyKey: casts[0].idempotencyKey });
    expect(retry.status).toBe(200);
    expect(retry.body.receipt).toEqual(receipts[0]);

    // ── same key, DIFFERENT payload → idempotency conflict ───────────────────
    const conflict = await request(app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 1 }, idempotencyKey: casts[0].idempotencyKey });
    expect(conflict.status).toBe(409);
    expect(conflict.body.code).toBe("IDEMPOTENCY_CONFLICT");

    // ── /root: 3 leaves, root === RFC 6962 root over served leaves ───────────
    const root = await request(app).get(`/root`).query({ decisionId: id });
    expect(root.status).toBe(200);
    expect(root.body.treeSize).toBe(3);

    // ── /ballots: DRAIN the cursor (M3) before recomputing the root ──────────
    const drained: Array<{ logSeq: number; payload: unknown; serial: string | null; ballotHash: string }> = [];
    let cursor: number | null = -1;
    let complete = false;
    while (!complete) {
      const page = await request(app)
        .get(`/ballots`)
        .query({ decisionId: id, after: cursor, limit: 2 });
      expect(page.status).toBe(200);
      drained.push(...page.body.ballots);
      complete = page.body.complete === true;
      cursor = page.body.nextCursor;
    }
    expect(drained).toHaveLength(3);
    // Open-mode leaves carry serial: null.
    for (const b of drained) expect(b.serial).toBe(null);

    // ── §11.5 binding: recompute the Merkle root from the drained public leaves
    const ordered = [...drained].sort((a, b) => a.logSeq - b.logSeq);
    const recomputedRoot = merkleRoot(ordered.map((b) => b.ballotHash));
    expect(recomputedRoot).toBe(root.body.root);
    // Each served ballotHash recomputes from the PUBLIC leaf recipe.
    for (const b of ordered) {
      expect(b.ballotHash).toBe(leafOf(id, b.logSeq, b.payload));
    }
    // The last receipt's runningRoot is the (now final) Merkle root.
    expect(receipts[2].runningRoot).toBe(root.body.root);

    // ── close → publish ──────────────────────────────────────────────────────
    expect((await auth(request(app).post(`/decisions/${id}/close`))).body.state).toBe("closed");
    expect((await auth(request(app).post(`/decisions/${id}/publish`))).body.state).toBe("published");

    // ── /anchor: broadcast bundle over the signed final root ─────────────────
    const anchor = await request(app).get(`/anchor`).query({ decisionId: id });
    expect(anchor.status).toBe(200);
    expect(anchor.body.mode).toBe("broadcast");
    expect(anchor.body.root).toBe(recomputedRoot);
    expect(anchor.body.treeSize).toBe(3);
    expect(typeof anchor.body.signedRoot).toBe("string");
    expect(anchor.body.signedRoot.length).toBeGreaterThan(0);

    // ── GET /verify/:id: the server-side convenience report, all 6 checks pass
    const verify = await request(app).get(`/verify/${id}`);
    expect(verify.status).toBe(200);
    const report = verify.body.report;
    expect(report.ok).toBe(true);
    expect(report.checks).toHaveLength(6);
    for (const c of report.checks as Check[]) {
      expect(c.ok, `§11 check '${c.name}' failed: ${c.detail}`).toBe(true);
    }
    // The verifier's OWN recompute: 2-1 carries with a majority for option 0.
    expect(report.tally.optionScores).toEqual([2, 1]);
    expect(report.verdict.outcome).toBe("carried");
    expect(report.verdict.winner).toBe(0);
  });

  it("a verifier rebuilds the bundle from public endpoints and verifyDecision passes", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);
    const id = await runToPublished(app, auth);

    const bundle = await buildBundleFromPublic(app, id);
    const report = verifyDecision(bundle);
    expect(report.ok).toBe(true);
    for (const c of report.checks) {
      expect(c.ok, `${c.name}: ${c.detail}`).toBe(true);
    }
  });

  it("tamper: mutating a served ballot in the bundle makes verifyDecision FAIL", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);
    const id = await runToPublished(app, auth);

    const bundle = await buildBundleFromPublic(app, id);
    // Sanity: the untampered bundle verifies.
    expect(verifyDecision(bundle).ok).toBe(true);

    // Flip the FIRST ballot's choice but keep its (now stale) ballotHash. The
    // leaf no longer recomputes → the 'leaves' check fails, and because the
    // tally now changes the published-result check would diverge too.
    const tampered: VerifierBundle = JSON.parse(JSON.stringify(bundle));
    const b0 = tampered.ballots.find((b) => b.logSeq === 0)!;
    (b0.payload as { kind: string; choice: number }).choice = 1;

    const report = verifyDecision(tampered);
    expect(report.ok).toBe(false);
    const leaves = report.checks.find((c) => c.name === "leaves")!;
    expect(leaves.ok).toBe(false);
  });

  it("tamper: swapping the anchor root breaks root-binding", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);
    const id = await runToPublished(app, auth);

    const bundle = await buildBundleFromPublic(app, id);
    const tampered: VerifierBundle = JSON.parse(JSON.stringify(bundle));
    // A root that does not match Merkle(ballots) and whose signature won't verify.
    tampered.anchor.root = "0".repeat(64);

    const report = verifyDecision(tampered);
    expect(report.ok).toBe(false);
    expect(report.checks.find((c) => c.name === "root-binding")!.ok).toBe(false);
  });

  it("rejects an unauth cast on a closed decision with a signed 409", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app).post("/decisions").send({ ...createBody, title: "Closed already", options: ["A", "B"] }),
    );
    const id: string = createRes.body.id;
    await auth(request(app).post(`/decisions/${id}/open`));
    await auth(request(app).post(`/decisions/${id}/close`));

    const res = await request(app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "late-1" });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("DECISION_CLOSED");
    expect(typeof res.body.signature).toBe("string");
    expect(res.body.signature.length).toBeGreaterThan(0);
  });

  // ── helpers ──────────────────────────────────────────────────────────────

  async function runToPublished(
    app: ReturnType<typeof makeTestApp>["app"],
    auth: (r: request.Test) => request.Test,
  ): Promise<string> {
    const createRes = await auth(request(app).post("/decisions").send(createBody));
    const id: string = createRes.body.id;
    await auth(request(app).post(`/decisions/${id}/open`));
    const casts = [
      { payload: { kind: "single", choice: 0 }, idempotencyKey: "p-a" },
      { payload: { kind: "single", choice: 0 }, idempotencyKey: "p-b" },
      { payload: { kind: "single", choice: 1 }, idempotencyKey: "p-c" },
    ];
    for (const c of casts) {
      await request(app)
        .post("/ballots")
        .send({ decisionId: id, payload: c.payload, idempotencyKey: c.idempotencyKey });
    }
    await auth(request(app).post(`/decisions/${id}/close`));
    await auth(request(app).post(`/decisions/${id}/publish`));
    return id;
  }

  /** Assemble a VerifierBundle PURELY from the public read endpoints. */
  async function buildBundleFromPublic(
    app: ReturnType<typeof makeTestApp>["app"],
    id: string,
  ): Promise<VerifierBundle> {
    const meta = (await request(app).get(`/decisions/${id}`)).body;
    const anchor = (await request(app).get(`/anchor`).query({ decisionId: id })).body;
    const results = (await request(app).get(`/results`).query({ decisionId: id })).body;
    const key = (await request(app).get(`/key`)).body;

    // Drain the public ballot log.
    const ballots: VerifierBundle["ballots"] = [];
    let cursor: number | null = -1;
    let complete = false;
    while (!complete) {
      const page = await request(app)
        .get(`/ballots`)
        .query({ decisionId: id, after: cursor, limit: 2 });
      for (const b of page.body.ballots) {
        ballots.push({
          logSeq: b.logSeq,
          payload: b.payload,
          serial: b.serial,
          ballotHash: b.ballotHash,
        });
      }
      complete = page.body.complete === true;
      cursor = page.body.nextCursor;
    }

    return {
      decision: {
        id: meta.id,
        title: meta.title,
        options: meta.options,
        method: meta.method,
        ballotMode: meta.ballotMode,
        resultsPolicy: meta.resultsPolicy,
        rule: meta.rule,
        schedule: meta.schedule,
        visibility: meta.visibility,
        anchorMode: meta.anchorMode,
        rosterCommitment: meta.rosterCommitment,
        issuerPubKeyHash: meta.issuerPubKeyHash,
      },
      setupCommitment: meta.setupCommitment,
      serverPubKeyPem: key.serverPubKeyPem,
      ballots,
      anchor: {
        root: anchor.root,
        treeSize: anchor.treeSize,
        signedRoot: anchor.signedRoot,
      },
      publishedResult: { tally: results.tally, verdict: results.verdict },
    };
  }
});
