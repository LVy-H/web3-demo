import request from "supertest";
import { describe, it, expect } from "vitest";
import { makeTestApp, type TestApp } from "../helpers/app";
import { reconcileExpiredDecisions } from "../../src/routes/reconcile";

const baseDecision = {
  title: "Q?",
  options: ["A", "B"],
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

describe("M2: startup reconcile auto-closes decisions past their effective close", () => {
  it("auto-closes an open decision whose scheduled close is in the past", async () => {
    // Clock fixed at 5000; closesAt 1000 is already past.
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t, { schedule: { closesAt: 1000 } });
    expect(t.repos.decisions.get(id)?.state).toBe("open");

    const closed = reconcileExpiredDecisions({
      repos: t.repos,
      serverKey: t.serverKey,
      now: () => 5000,
    });

    expect(closed).toContain(id);
    expect(t.repos.decisions.get(id)?.state).toBe("closed");
    // A signed lifecycle 'closed' event was recorded by the reconcile actor.
    const events = t.repos.lifecycle.byDecision(id);
    expect(
      events.some(
        (e) => e.transition === "closed" && e.actor === "system:reconcile",
      ),
    ).toBe(true);
  });

  it("leaves an open decision whose close is in the FUTURE untouched", async () => {
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t, { schedule: { closesAt: 9000 } });
    const closed = reconcileExpiredDecisions({
      repos: t.repos,
      serverKey: t.serverKey,
      now: () => 5000,
    });
    expect(closed).not.toContain(id);
    expect(t.repos.decisions.get(id)?.state).toBe("open");
  });

  it("leaves a manual-close (no schedule, no extend) decision open", async () => {
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t); // schedule {}
    const closed = reconcileExpiredDecisions({
      repos: t.repos,
      serverKey: t.serverKey,
      now: () => 5000,
    });
    expect(closed).not.toContain(id);
    expect(t.repos.decisions.get(id)?.state).toBe("open");
  });

  it("respects an extend that pushes the effective close into the future", async () => {
    const t = makeTestApp({ now: () => 5000 });
    const id = await createOpen(t, { schedule: { closesAt: 1000 } });
    // Extend past now → effective close 9000 > 5000 → NOT auto-closed.
    await auth(t, request(t.app).post(`/decisions/${id}/extend`).send({ closesAt: 9000 }));
    const closed = reconcileExpiredDecisions({
      repos: t.repos,
      serverKey: t.serverKey,
      now: () => 5000,
    });
    expect(closed).not.toContain(id);
    expect(t.repos.decisions.get(id)?.state).toBe("open");
  });
});
