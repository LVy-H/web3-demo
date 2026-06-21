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
    const page2 = await request(t.app)
      .get(`/ballots`)
      .query({ decisionId: id, after: page1.body.nextCursor, limit: 2 });
    expect(page2.body.ballots).toHaveLength(1);
    expect(page2.body.nextCursor).toBe(null);
  });
});
