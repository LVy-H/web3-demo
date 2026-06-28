import { describe, it, expect } from "vitest";
import { runCli } from "../src/cli";

function fakeFetch(routes: Record<string, { status: number; body: unknown }>) {
  return (async (url: string, init?: RequestInit) => {
    const key = `${init?.method ?? "GET"} ${new URL(url).pathname}`;
    const r = routes[key] ?? { status: 404, body: { error: "nf" } };
    return { ok: r.status < 400, status: r.status, json: async () => r.body } as Response;
  }) as unknown as typeof fetch;
}
const env = { TESSERA_ADMIN_URL: "http://127.0.0.1:8786", TESSERA_OPERATOR_TOKEN: "t" };

describe("tessera-ctl", () => {
  it("create prints the slug + handed-over admin token", async () => {
    const f = fakeFetch({ "POST /tenants": { status: 201, body: { slug: "acme", adminToken: "TOK" } } });
    const r = await runCli(["create", "acme", "--display-name", "Acme"], env, f);
    expect(r.code).toBe(0); expect(r.out).toMatch(/acme/); expect(r.out).toMatch(/TOK/);
  });
  it("list renders rows", async () => {
    const f = fakeFetch({ "GET /tenants": { status: 200, body: { tenants: [{ slug: "acme", status: "active" }] } } });
    const r = await runCli(["list"], env, f);
    expect(r.code).toBe(0); expect(r.out).toMatch(/acme\s+active/);
  });
  it("non-zero exit on API error", async () => {
    const f = fakeFetch({ "POST /tenants": { status: 409, body: { error: "exists" } } });
    const r = await runCli(["create", "acme"], env, f);
    expect(r.code).toBe(1); expect(r.out).toMatch(/exists/);
  });
});
