import request from "supertest";
import { describe, it, expect } from "vitest";
import { makeTestApp } from "../helpers/app";
import {
  canonicalize,
  sha256hex,
  genesisHead,
  chainNext,
} from "../../src/crypto";

/**
 * §11.5 binding check, end-to-end:
 *   create → open → cast×3 (one idempotent retry) → close → publish,
 * then recompute the hash-chain off the served ballots and assert it equals
 * the server's published /root head, and that /results matches a hand-tally.
 */
describe("e2e: open-ballot decision flow", () => {
  const ballotHashOf = (decisionId: string, payload: unknown, idempotencyKey: string) =>
    sha256hex(
      "tessera:ballot:v1\n" +
        canonicalize({ decisionId, payload, idempotencyKey }),
    );

  it("runs create→open→cast→close→publish and binds /root to the recomputed chain", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);

    // ── create (convener) ────────────────────────────────────────────────────
    const createRes = await auth(
      request(app)
        .post("/decisions")
        .send({
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
        }),
    );
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
    for (const c of casts) {
      const res = await request(app)
        .post("/ballots")
        .send({ decisionId: id, payload: c.payload, idempotencyKey: c.idempotencyKey });
      expect(res.status).toBe(201);
      expect(res.body.receipt.ballotHash).toBe(
        ballotHashOf(id, c.payload, c.idempotencyKey),
      );
      receipts.push(res.body.receipt);
    }

    // ── idempotent retry of the first ballot returns the SAME receipt ─────────
    const retry = await request(app)
      .post("/ballots")
      .send({ decisionId: id, payload: casts[0].payload, idempotencyKey: casts[0].idempotencyKey });
    expect(retry.status).toBe(200);
    expect(retry.body.receipt).toEqual(receipts[0]);

    // ── /root: 3 leaves ──────────────────────────────────────────────────────
    const root = await request(app).get(`/root`).query({ decisionId: id });
    expect(root.status).toBe(200);
    expect(root.body.leafCount).toBe(3);

    // ── /ballots: DRAIN the cursor (M3) before recomputing the head ──────────
    // A verifier must page until `complete` so a >limit log can't silently
    // truncate the recomputation. Use a small limit to exercise pagination.
    const drained: Array<{ ballotHash: string }> = [];
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

    // ── §11.5 binding: independently recompute the chain from the drained log ─
    let head = genesisHead(id);
    for (const b of drained) {
      head = chainNext(head, b.ballotHash);
    }
    expect(head).toBe(root.body.head);

    // The last receipt's runningRoot is the published head.
    expect(receipts[2].runningRoot).toBe(root.body.head);

    // ── close → publish ──────────────────────────────────────────────────────
    const close = await auth(request(app).post(`/decisions/${id}/close`));
    expect(close.status).toBe(200);
    expect(close.body.state).toBe("closed");

    const publish = await auth(request(app).post(`/decisions/${id}/publish`));
    expect(publish.status).toBe(200);
    expect(publish.body.state).toBe("published");

    // ── /results: option 0 carries with a majority ───────────────────────────
    const results = await request(app).get(`/results`).query({ decisionId: id });
    expect(results.status).toBe(200);
    expect(results.body.authoritative).toBe(false);
    expect(results.body.tally.optionScores).toEqual([2, 1]);
    expect(results.body.verdict.outcome).toBe("carried");
    expect(results.body.verdict.winner).toBe(0);
  });

  it("M3: a drained >limit page recomputation equals /root (no silent truncation)", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app)
        .post("/decisions")
        .send({
          title: "Many ballots",
          options: ["Yes", "No"],
          method: "single",
          ballotMode: "open",
          resultsPolicy: "live",
          eligibility: { method: "open" },
          rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
          schedule: {},
          visibility: "listed",
          anchorMode: "broadcast",
        }),
    );
    const id: string = createRes.body.id;
    await auth(request(app).post(`/decisions/${id}/open`));

    // Cast 3 ballots; page with limit 2 (so the first page is NOT complete).
    for (let i = 0; i < 3; i++) {
      const res = await request(app)
        .post("/ballots")
        .send({ decisionId: id, payload: { kind: "single", choice: i % 2 }, idempotencyKey: `m3-${i}` });
      expect(res.status).toBe(201);
    }

    // First page (limit 2) must report complete=false and a nextCursor.
    const page1 = await request(app).get(`/ballots`).query({ decisionId: id, limit: 2 });
    expect(page1.body.ballots).toHaveLength(2);
    expect(page1.body.complete).toBe(false);
    expect(page1.body.nextCursor).toBe(1);

    // A naive single-page recomputation would DIVERGE from /root.
    const root = await request(app).get(`/root`).query({ decisionId: id });
    let truncated = genesisHead(id);
    for (const b of page1.body.ballots) truncated = chainNext(truncated, b.ballotHash);
    expect(truncated).not.toBe(root.body.head);

    // Draining the cursor until complete recomputes the SAME head as /root.
    const drained: Array<{ ballotHash: string }> = [];
    let cursor: number | null = -1;
    let complete = false;
    while (!complete) {
      const page: request.Response = await request(app)
        .get(`/ballots`)
        .query({ decisionId: id, after: cursor, limit: 2 });
      drained.push(...page.body.ballots);
      complete = page.body.complete === true;
      cursor = page.body.nextCursor;
    }
    expect(drained).toHaveLength(3);
    let head = genesisHead(id);
    for (const b of drained) head = chainNext(head, b.ballotHash);
    expect(head).toBe(root.body.head);
  });

  it("rejects an unauth cast on a closed decision with a signed 409", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) => r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app)
        .post("/decisions")
        .send({
          title: "Closed already",
          options: ["A", "B"],
          method: "single",
          ballotMode: "open",
          resultsPolicy: "live",
          eligibility: { method: "open" },
          rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
          schedule: {},
          visibility: "listed",
          anchorMode: "broadcast",
        }),
    );
    const id: string = createRes.body.id;
    await auth(request(app).post(`/decisions/${id}/open`));
    await auth(request(app).post(`/decisions/${id}/close`));

    const res = await request(app)
      .post("/ballots")
      .send({
        decisionId: id,
        payload: { kind: "single", choice: 0 },
        idempotencyKey: "late-1",
      });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("DECISION_CLOSED");
    expect(typeof res.body.signature).toBe("string");
    expect(res.body.signature.length).toBeGreaterThan(0);
  });
});
