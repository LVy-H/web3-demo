import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos, DuplicateTenantError } from "../../src/registry/repos";

let repos: ReturnType<typeof makeRepos>;
beforeEach(() => { const db = openDb(":memory:"); migrate(db); repos = makeRepos(db); });

describe("TenantRepo", () => {
  it("creates with derived names + provisioning status", () => {
    const t = repos.tenants.create({ slug: "acme", displayName: "Acme" });
    expect(t).toMatchObject({
      slug: "acme", displayName: "Acme", status: "provisioning",
      containerName: "tessera-acme", volumeName: "tessera-acme",
      internalPort: 3001, keyFingerprint: null,
    });
    expect(repos.tenants.get("acme")?.slug).toBe("acme");
    expect(repos.tenants.list()).toHaveLength(1);
  });
  it("rejects a duplicate slug", () => {
    repos.tenants.create({ slug: "acme", displayName: "Acme" });
    expect(() => repos.tenants.create({ slug: "acme", displayName: "X" })).toThrow(DuplicateTenantError);
  });
  it("updates status + fingerprint, and removes", () => {
    repos.tenants.create({ slug: "acme", displayName: "Acme" });
    repos.tenants.setStatus("acme", "active");
    repos.tenants.setFingerprint("acme", "abc123");
    const t = repos.tenants.get("acme")!;
    expect(t.status).toBe("active"); expect(t.keyFingerprint).toBe("abc123");
    repos.tenants.remove("acme");
    expect(repos.tenants.get("acme")).toBeNull();
  });
});

describe("OperatorRepo", () => {
  it("counts, creates, finds by token hash", () => {
    expect(repos.operators.count()).toBe(0);
    repos.operators.create("hash-1");
    expect(repos.operators.count()).toBe(1);
    expect(repos.operators.findByTokenHash("hash-1")).not.toBeNull();
    expect(repos.operators.findByTokenHash("nope")).toBeNull();
  });
});
