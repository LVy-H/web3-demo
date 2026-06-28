import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { slugFromHost, resolveRoute } from "../../src/proxy/hostRouter";
import { loadConfig } from "../../src/config";

const config = loadConfig({});
let repos: ReturnType<typeof makeRepos>;
beforeEach(() => { const db = openDb(":memory:"); migrate(db); repos = makeRepos(db); });

describe("slugFromHost", () => {
  it("extracts the org label, ignoring the port", () => {
    expect(slugFromHost("acme.localhost:8787", "localhost")).toBe("acme");
    expect(slugFromHost("acme.localhost", "localhost")).toBe("acme");
  });
  it("rejects bare base domain or wrong suffix", () => {
    expect(slugFromHost("localhost:8787", "localhost")).toBeNull();
    expect(slugFromHost("acme.example.com", "localhost")).toBeNull();
    expect(slugFromHost(undefined, "localhost")).toBeNull();
    expect(slugFromHost("a.b.localhost", "localhost")).toBeNull(); // exactly one label
  });
});

describe("resolveRoute", () => {
  it("routes an active tenant to its instance", () => {
    repos.tenants.create({ slug: "acme", displayName: "Acme" });
    repos.tenants.setStatus("acme", "active");
    expect(resolveRoute(repos, config, "acme.localhost:8787"))
      .toEqual({ kind: "ok", target: "http://tessera-acme:3001" });
  });
  it("maps status + bad host to the right decision", () => {
    expect(resolveRoute(repos, config, "ghost.localhost")).toEqual({ kind: "notFound" });
    repos.tenants.create({ slug: "s", displayName: "S" }); repos.tenants.setStatus("s", "suspended");
    expect(resolveRoute(repos, config, "s.localhost")).toEqual({ kind: "suspended" });
    repos.tenants.create({ slug: "m", displayName: "M" }); repos.tenants.setStatus("m", "key-mismatch");
    expect(resolveRoute(repos, config, "m.localhost")).toEqual({ kind: "mismatch" });
    expect(resolveRoute(repos, config, "localhost")).toEqual({ kind: "badHost" });
  });
});
