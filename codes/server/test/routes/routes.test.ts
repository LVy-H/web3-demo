import request from "supertest";
import { describe, it, expect } from "vitest";
import { makeTestApp, type TestApp } from "../helpers/app";
import { hashToken, mintConvenerToken } from "../../src/auth";
import { verifySig, canonicalize } from "../../src/crypto";

const baseDecision = {
  title: "Q?",
  options: ["A", "B", "C"],
  method: "single",
  ballotMode: "open",
  resultsPolicy: "live",
  eligibility: { method: "open" },
  rule: { threshold: { kind: "plurality" }, tieBreak: "declare" },
  schedule: {},
  visibility: "listed",
  anchorMode: "broadcast",
};

function auth(t: TestApp, r: request.Test) {
  return r.set("Authorization", `Bearer ${t.adminToken}`);
}

async function createOpen(t: TestApp, overrides: Record<string, unknown> = {}) {
  const c = await auth(
    t,
    request(t.app).post("/decisions").send({ ...baseDecision, ...overrides }),
  );
  const id = c.body.id as string;
  await auth(t, request(t.app).post(`/decisions/${id}/open`));
  return id;
}

describe("convener routes", () => {
  it("rejects an unauthenticated POST /decisions with 401", async () => {
    const t = makeTestApp();
    const res = await request(t.app).post("/decisions").send(baseDecision);
    expect(res.status).toBe(401);
  });

  it("validates the create body (400 VALIDATION)", async () => {
    const t = makeTestApp();
    const res = await auth(
      t,
      request(t.app).post("/decisions").send({ ...baseDecision, options: ["only-one"] }),
    );
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("VALIDATION");
    expect(Array.isArray(res.body.issues)).toBe(true);
  });

  it("404s an open on a missing decision", async () => {
    const t = makeTestApp();
    const res = await auth(t, request(t.app).post(`/decisions/nope/open`));
    expect(res.status).toBe(404);
  });

  it("403s when a different convener acts on the decision", async () => {
    const t = makeTestApp();
    const id = (
      await auth(t, request(t.app).post("/decisions").send(baseDecision))
    ).body.id as string;
    const { token: other } = mintConvenerToken(t.repos, "other");
    const res = await request(t.app)
      .post(`/decisions/${id}/open`)
      .set("Authorization", `Bearer ${other}`);
    expect(res.status).toBe(403);
    expect(res.body.code).toBe("FORBIDDEN");
  });

  it("409 ILLEGAL_TRANSITION on an out-of-order transition", async () => {
    const t = makeTestApp();
    const id = (
      await auth(t, request(t.app).post("/decisions").send(baseDecision))
    ).body.id as string;
    // draft → published is illegal (must open/close first).
    const res = await auth(t, request(t.app).post(`/decisions/${id}/publish`));
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("ILLEGAL_TRANSITION");
    expect(res.body.from).toBe("draft");
    expect(res.body.to).toBe("published");
  });

  it("C1: re-opening an already-open decision is 409 and does NOT reset /root", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    // Cast 3 ballots so the chain advances to leafCount 3.
    for (let i = 0; i < 3; i++) {
      await request(t.app)
        .post("/ballots")
        .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: `c1-${i}` });
    }
    const before = await request(t.app).get(`/root`).query({ decisionId: id });
    expect(before.body.leafCount).toBe(3);
    const headBefore = before.body.head as string;
    expect(headBefore).not.toBe("");

    // A SECOND /open must be rejected (open is no longer a self-transition) and
    // must NOT re-init the head to genesis/leafCount-0 (the C1 chain-fork bug).
    const reopen = await auth(t, request(t.app).post(`/decisions/${id}/open`));
    expect(reopen.status).toBe(409);
    expect(reopen.body.code).toBe("ILLEGAL_TRANSITION");
    expect(reopen.body.from).toBe("open");
    expect(reopen.body.to).toBe("open");

    const after = await request(t.app).get(`/root`).query({ decisionId: id });
    expect(after.body.leafCount).toBe(3);
    expect(after.body.head).toBe(headBefore);
  });

  it("extend keeps state open and signs the amendment", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await auth(
      t,
      request(t.app).post(`/decisions/${id}/extend`).send({ closesAt: 9_999 }),
    );
    expect(res.status).toBe(200);
    expect(res.body.state).toBe("open");
    expect(res.body.closesAt).toBe(9_999);
    // The decision row is not mutated out of 'open'.
    const view = await request(t.app).get(`/decisions/${id}`);
    expect(view.body.state).toBe("open");
    // A signed lifecycle 'extend' event was recorded.
    const events = t.repos.lifecycle.byDecision(id);
    expect(events.some((e) => e.transition === "extend")).toBe(true);
  });

  it("extend requires an integer closesAt", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await auth(
      t,
      request(t.app).post(`/decisions/${id}/extend`).send({ closesAt: "soon" }),
    );
    expect(res.status).toBe(400);
  });

  it("turnout counts ballots", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "k1" });
    const res = await auth(t, request(t.app).get(`/decisions/${id}/turnout`));
    expect(res.status).toBe(200);
    expect(res.body.count).toBe(1);
  });

  it("signs lifecycle events verifiably (open)", async () => {
    const t = makeTestApp();
    const id = (
      await auth(t, request(t.app).post("/decisions").send(baseDecision))
    ).body.id as string;
    await auth(t, request(t.app).post(`/decisions/${id}/open`));
    const [ev] = t.repos.lifecycle.byDecision(id);
    const preimage = canonicalize({
      decisionId: id,
      from: "draft",
      to: "open",
      actor: ev.actor,
      timestamp: ev.ts,
    });
    expect(verifySig(t.serverKey.publicKeyPem, preimage, ev.signedSig)).toBe(true);
  });
});

describe("participant cast", () => {
  it("404s a cast on a missing decision", async () => {
    const t = makeTestApp();
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: "ghost", payload: { kind: "single", choice: 0 }, idempotencyKey: "k" });
    expect(res.status).toBe(404);
  });

  it("rejects a malformed payload (400 VALIDATION)", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 99 }, idempotencyKey: "k" });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("VALIDATION");
  });

  it("requires a non-empty idempotencyKey", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "" });
    expect(res.status).toBe(400);
  });

  it("returns the SAME receipt on an identical retry (200)", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const body = { decisionId: id, payload: { kind: "single", choice: 1 }, idempotencyKey: "dup" };
    const first = await request(t.app).post("/ballots").send(body);
    expect(first.status).toBe(201);
    const second = await request(t.app).post("/ballots").send(body);
    expect(second.status).toBe(200);
    expect(second.body.receipt).toEqual(first.body.receipt);
  });

  it("409 IDEMPOTENCY_CONFLICT on same key, different payload", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "x" });
    const conflict = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 1 }, idempotencyKey: "x" });
    expect(conflict.status).toBe(409);
    expect(conflict.body.code).toBe("IDEMPOTENCY_CONFLICT");
  });

  it("the closed rejection signature verifies", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    await auth(t, request(t.app).post(`/decisions/${id}/close`));
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "late" });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("DECISION_CLOSED");
    const preimage = canonicalize({ error: "decision-closed", decisionId: id });
    expect(verifySig(t.serverKey.publicKeyPem, preimage, res.body.signature)).toBe(true);
  });

  describe("eligibility", () => {
    it("passcode: wrong passcode → signed 403 INELIGIBLE; correct → 201", async () => {
      const t = makeTestApp();
      // Create with passcode eligibility (passcode in the create body), then
      // open. The route stores the passcode HASH as an eligibility record.
      const id = await createOpen(t, {
        eligibility: { method: "passcode", passcode: "s3cret" },
      });
      // The route persisted the hashed passcode at create time.
      expect(t.repos.eligibility.find(id, hashToken("s3cret"))).not.toBeNull();

      const bad = await request(t.app).post("/ballots").send({
        decisionId: id,
        payload: { kind: "single", choice: 0 },
        idempotencyKey: "p-bad",
        passcode: "wrong",
      });
      expect(bad.status).toBe(403);
      expect(bad.body.code).toBe("INELIGIBLE");
      const preimage = canonicalize({ error: "ineligible", decisionId: id });
      expect(verifySig(t.serverKey.publicKeyPem, preimage, bad.body.signature)).toBe(true);

      const ok = await request(t.app).post("/ballots").send({
        decisionId: id,
        payload: { kind: "single", choice: 0 },
        idempotencyKey: "p-ok",
        passcode: "s3cret",
      });
      expect(ok.status).toBe(201);
    });

    it("domain: wrong domain → 403; matching → 201", async () => {
      const t = makeTestApp();
      const id = await createOpen(t, {
        eligibility: { method: "domain", domain: "example.org" },
      });
      const bad = await request(t.app).post("/ballots").send({
        decisionId: id,
        payload: { kind: "single", choice: 0 },
        idempotencyKey: "d-bad",
        email: "user@other.com",
      });
      expect(bad.status).toBe(403);
      const ok = await request(t.app).post("/ballots").send({
        decisionId: id,
        payload: { kind: "single", choice: 0 },
        idempotencyKey: "d-ok",
        email: "user@example.org",
      });
      expect(ok.status).toBe(201);
    });
  });

  it("M1: rate-limits POST /ballots with 429 once the per-window cap is hit", async () => {
    // Cap at 2 casts per window; the 3rd distinct ballot is throttled.
    const t = makeTestApp({ config: { ballotRateLimit: { windowMs: 60_000, max: 2 } } });
    const id = await createOpen(t);
    const cast = (k: string) =>
      request(t.app)
        .post("/ballots")
        .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: k });
    expect((await cast("rl-1")).status).toBe(201);
    expect((await cast("rl-2")).status).toBe(201);
    const throttled = await cast("rl-3");
    expect(throttled.status).toBe(429);
  });

  it("M2: rejects a cast once maxParticipants is reached (signed 409 MAX_PARTICIPANTS)", async () => {
    const t = makeTestApp();
    const id = await createOpen(t, { maxParticipants: 2 });
    const cast = (k: string) =>
      request(t.app)
        .post("/ballots")
        .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: k });
    expect((await cast("m2-1")).status).toBe(201);
    expect((await cast("m2-2")).status).toBe(201);
    const full = await cast("m2-3");
    expect(full.status).toBe(409);
    expect(full.body.code).toBe("MAX_PARTICIPANTS");
    expect(full.body.error).toBe("decision-full");
    // Signed, like decision-closed — an exhibitable refusal.
    const preimage = canonicalize({ error: "decision-full", decisionId: id });
    expect(verifySig(t.serverKey.publicKeyPem, preimage, full.body.signature)).toBe(true);
  });

  it("M2: rejects a cast after the scheduled close has passed (signed DECISION_CLOSED)", async () => {
    // Fixed clock at t=5000; schedule closesAt=1000 is already in the past.
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t, { schedule: { closesAt: 1000 } });
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "late" });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("DECISION_CLOSED");
    const preimage = canonicalize({ error: "decision-closed", decisionId: id });
    expect(verifySig(t.serverKey.publicKeyPem, preimage, res.body.signature)).toBe(true);
  });

  it("M2: an extend pushes the effective close out, re-admitting a cast", async () => {
    // Clock at t=5000; original close 1000 (past) but an extend to 9000 (future)
    // makes the effective close 9000 → the cast is admitted.
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t, { schedule: { closesAt: 1000 } });
    await auth(t, request(t.app).post(`/decisions/${id}/extend`).send({ closesAt: 9000 }));
    const res = await request(t.app)
      .post("/ballots")
      .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: "ext-ok" });
    expect(res.status).toBe(201);
  });

  it("quadratic: over-budget votes → 400 BUDGET_EXCEEDED", async () => {
    const t = makeTestApp();
    const id = await createOpen(t, { method: "quadratic" });
    // 3 options; votes [9,9,0] → 81+81 = 162 > 100.
    const res = await request(t.app).post("/ballots").send({
      decisionId: id,
      payload: { kind: "quadratic", votes: [9, 9, 0] },
      idempotencyKey: "q1",
    });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("BUDGET_EXCEEDED");
  });
});

describe("public routes", () => {
  it("GET /decisions/:id never exposes tokens and reports trustLevel", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await request(t.app).get(`/decisions/${id}`);
    expect(res.status).toBe(200);
    expect(res.body.trustLevel).toBe("broadcast");
    expect(res.body.state).toBe("open");
    expect(JSON.stringify(res.body)).not.toContain("tokenHash");
  });

  it("GET /decisions/:id 404 on missing", async () => {
    const t = makeTestApp();
    const res = await request(t.app).get(`/decisions/ghost`);
    expect(res.status).toBe(404);
  });

  it("GET /root 404 on missing decision", async () => {
    const t = makeTestApp();
    const res = await request(t.app).get(`/root`).query({ decisionId: "ghost" });
    expect(res.status).toBe(404);
  });

  it("GET /anchor reports mode + status", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    const res = await request(t.app).get(`/anchor`).query({ decisionId: id });
    expect(res.status).toBe(200);
    expect(res.body.mode).toBe("broadcast");
    expect(res.body.status).toBe("broadcast");
  });

  it("GET /ballots paginates with a nextCursor", async () => {
    const t = makeTestApp();
    const id = await createOpen(t);
    for (let i = 0; i < 3; i++) {
      await request(t.app)
        .post("/ballots")
        .send({ decisionId: id, payload: { kind: "single", choice: 0 }, idempotencyKey: `k${i}` });
    }
    const page1 = await request(t.app).get(`/ballots`).query({ decisionId: id, limit: 2 });
    expect(page1.body.ballots).toHaveLength(2);
    expect(page1.body.leafCount).toBe(3);
    expect(page1.body.nextCursor).toBe(1);
    // M3: not the end of the stream yet.
    expect(page1.body.complete).toBe(false);
    const page2 = await request(t.app)
      .get(`/ballots`)
      .query({ decisionId: id, after: page1.body.nextCursor, limit: 2 });
    expect(page2.body.ballots).toHaveLength(1);
    expect(page2.body.nextCursor).toBe(null);
    // M3: the final page reaches the end.
    expect(page2.body.complete).toBe(true);
  });
});
