import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { makeProvisioner } from "../../src/orchestrator/provisioner";
import { FakeRuntime } from "../support/fakeRuntime";
import { loadConfig } from "../../src/config";
import { createAdminApp } from "../../src/admin/routes";
import { hashToken } from "../../src/admin/auth";

const TOKEN = "op-token-xyz";
function app() {
  const db = openDb(":memory:"); migrate(db); const repos = makeRepos(db);
  repos.operators.create(hashToken(TOKEN));
  const provisioner = makeProvisioner({
    repos, runtime: new FakeRuntime(), config: loadConfig({}),
    fetchFp: async () => "FP", waitHealthy: async () => {},
  });
  return createAdminApp({ repos, provisioner });
}
const auth = (r: request.Test) => r.set("Authorization", `Bearer ${TOKEN}`);

describe("admin API", () => {
  it("401 without a valid operator token", async () => {
    await request(app()).get("/tenants").expect(401);
  });
  it("create → list → suspend → resume → delete", async () => {
    const a = app();
    const c = await auth(request(a).post("/tenants").send({ slug: "acme", displayName: "Acme" }));
    expect(c.status).toBe(201); expect(c.body.adminToken).toBe("TENANTTOK");
    const l = await auth(request(a).get("/tenants"));
    expect(l.body.tenants.map((t: { slug: string }) => t.slug)).toEqual(["acme"]);
    expect((await auth(request(a).post("/tenants/acme/suspend"))).body.status).toBe("suspended");
    expect((await auth(request(a).post("/tenants/acme/resume"))).body.status).toBe("active");
    expect((await auth(request(a).delete("/tenants/acme"))).body.deleted).toBe(true);
  });
  it("400 invalid slug, 409 duplicate, 404 unknown", async () => {
    const a = app();
    expect((await auth(request(a).post("/tenants").send({ slug: "Bad", displayName: "x" }))).status).toBe(400);
    await auth(request(a).post("/tenants").send({ slug: "acme", displayName: "A" }));
    expect((await auth(request(a).post("/tenants").send({ slug: "acme", displayName: "B" }))).status).toBe(409);
    expect((await auth(request(a).post("/tenants/ghost/suspend"))).status).toBe(404);
  });
});
