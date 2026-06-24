import { describe, it, expect, afterEach } from "vitest";
import http from "node:http";
import { AddressInfo } from "node:net";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { createProxyServer } from "../../src/proxy/proxy";
import { loadConfig } from "../../src/config";

const servers: http.Server[] = [];
afterEach(() => { for (const s of servers) s.close(); servers.length = 0; });
const listen = (s: http.Server) => new Promise<number>((r) => { servers.push(s); s.listen(0, () => r((s.address() as AddressInfo).port)); });
const get = (port: number, host: string, path = "/") => new Promise<{ status: number; body: string }>((res, rej) => {
  http.get({ port, path, headers: { host } }, (r) => { let b = ""; r.on("data", (c) => (b += c)); r.on("end", () => res({ status: r.statusCode!, body: b })); }).on("error", rej);
});

describe("proxy server", () => {
  it("proxies an active tenant to its upstream and returns the upstream body", async () => {
    const upstream = http.createServer((_q, s) => { s.writeHead(200); s.end("from-upstream"); });
    const upPort = await listen(upstream);
    const db = openDb(":memory:"); migrate(db); const repos = makeRepos(db);
    // point the tenant's target at our local upstream via a config override:
    repos.tenants.create({ slug: "acme", displayName: "Acme" }); repos.tenants.setStatus("acme", "active");
    const config = { ...loadConfig({}), baseDomain: "localhost" };
    const proxy = createProxyServer({ repos, config, targetOverride: () => `http://127.0.0.1:${upPort}` });
    const port = await listen(proxy);
    const r = await get(port, "acme.localhost");
    expect(r.status).toBe(200); expect(r.body).toBe("from-upstream");
  });

  it("returns 404 unknown / 421 bad host", async () => {
    const db = openDb(":memory:"); migrate(db); const repos = makeRepos(db);
    const proxy = createProxyServer({ repos, config: loadConfig({}) });
    const port = await listen(proxy);
    expect((await get(port, "ghost.localhost")).status).toBe(404);
    expect((await get(port, "localhost")).status).toBe(421);
  });
});
