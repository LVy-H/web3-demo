import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { makeProvisioner } from "../../src/orchestrator/provisioner";
import { FakeRuntime } from "../support/fakeRuntime";
import { loadConfig } from "../../src/config";

function setup(fp = "FP1") {
  const db = openDb(":memory:"); migrate(db);
  const repos = makeRepos(db);
  const runtime = new FakeRuntime();
  let current = fp;
  const prov = makeProvisioner({
    repos, runtime, config: loadConfig({}),
    fetchFp: async () => current,
    waitHealthy: async () => {},
  });
  return { repos, runtime, prov, setFp: (v: string) => { current = v; } };
}

describe("provisioner", () => {
  it("create: provisions, pins fingerprint, returns the tenant admin token", async () => {
    const { repos, runtime, prov } = setup();
    const { adminToken } = await prov.create("acme", "Acme");
    expect(adminToken).toBe("TENANTTOK");
    const t = repos.tenants.get("acme")!;
    expect(t.status).toBe("active");
    expect(t.keyFingerprint).toBe("FP1");
    expect(runtime.calls).toContain("run:tessera-acme");
    expect(runtime.running.has("tessera-acme")).toBe(true);
  });

  it("create: rejects an invalid slug before touching the runtime", async () => {
    const { runtime, prov } = setup();
    await expect(prov.create("Bad_Slug", "x")).rejects.toThrow();
    expect(runtime.calls).toHaveLength(0);
  });

  it("suspend stops the container; resume starts it again", async () => {
    const { repos, runtime, prov } = setup();
    await prov.create("acme", "Acme");
    await prov.suspend("acme");
    expect(repos.tenants.get("acme")!.status).toBe("suspended");
    expect(runtime.running.has("tessera-acme")).toBe(false);
    await prov.resume("acme");
    expect(repos.tenants.get("acme")!.status).toBe("active");
    expect(runtime.running.has("tessera-acme")).toBe(true);
  });

  it("resume flags key-mismatch when the fingerprint changed", async () => {
    const { repos, prov, setFp } = setup();
    await prov.create("acme", "Acme");
    await prov.suspend("acme");
    setFp("DIFFERENT");
    await prov.resume("acme");
    expect(repos.tenants.get("acme")!.status).toBe("key-mismatch");
  });

  it("remove tears down container + volume + registry row", async () => {
    const { repos, runtime, prov } = setup();
    await prov.create("acme", "Acme");
    await prov.remove("acme");
    expect(repos.tenants.get("acme")).toBeNull();
    expect(runtime.calls).toContain("rm:tessera-acme");
    expect(runtime.calls).toContain("vol-:tessera-acme");
  });
});
