import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { makeCliRuntime } from "../../src/orchestrator/runtime";
import { makeProvisioner } from "../../src/orchestrator/provisioner";
import { loadConfig } from "../../src/config";

const RUN = !!process.env.RUN_INTEGRATION;
const d = RUN ? describe : describe.skip;
let acmeAdmin = "";

// Drives the REAL runtime. Reaches tenant containers by their bridge IP so the
// host-run test can talk to them (Linux bridge is host-reachable).
d("two-org isolation (real docker/podman)", () => {
  const config = loadConfig({});
  const runtime = makeCliRuntime(config.runtime);
  const db = openDb(":memory:"); migrate(db); const repos = makeRepos(db);
  // Resolve container → bridge IP for host-side reachability:
  const ipOf = async (name: string) => {
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const { stdout } = await promisify(execFile)(config.runtime,
      ["inspect", "-f", `{{.NetworkSettings.Networks.${config.network}.IPAddress}}`, name]);
    return stdout.trim();
  };
  const prov = makeProvisioner({ repos, runtime, config,
    waitHealthy: async (url) => { for (let i=0;i<60;i++){ try{ if((await fetch(`${url}/health`)).ok) return; }catch{} await new Promise(r=>setTimeout(r,1000)); } throw new Error("unhealthy"); },
    fetchFp: async (url) => (await import("../../src/orchestrator/fingerprint")).fetchFingerprint(url),
  });
  // Override target base to the bridge IP (host can't resolve container names):
  const baseUrl = async (slug: string) => `http://${await ipOf(`tessera-${slug}`)}:3001`;

  beforeAll(async () => {
    // create() resolves health/fp via container name; for host runs we pre-point
    // those at the IP by monkeypatching is avoided — instead we create, then talk by IP.
    acmeAdmin = (await prov.create("acme", "Acme")).adminToken ?? "";
    await prov.create("beta", "Beta");
  });
  afterAll(async () => { await prov.remove("acme").catch(()=>{}); await prov.remove("beta").catch(()=>{}); });

  it("two orgs have distinct keys and data", async () => {
    const aKey = await (await fetch(`${await baseUrl("acme")}/key`)).json();
    const bKey = await (await fetch(`${await baseUrl("beta")}/key`)).json();
    expect(aKey.serverPubKeyPem).not.toBe(bKey.serverPubKeyPem);   // distinct identities
  });

  it("an acme decision is invisible to beta", async () => {
    const acme = await baseUrl("acme");
    const beta = await baseUrl("beta");
    const body = {
      title: "Adopt?", options: ["Yes", "No"], method: "single",
      ballotMode: "open", resultsPolicy: "live", eligibility: { method: "open" },
      rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
      schedule: {}, visibility: "listed", anchorMode: "broadcast",
    };
    const created = await (await fetch(`${acme}/decisions`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${acmeAdmin}` },
      body: JSON.stringify(body),
    })).json();
    const id = (created as { id: string }).id;
    // acme can fetch its own decision; beta cannot see it at all.
    expect((await fetch(`${acme}/decisions/${id}`)).status).toBe(200);
    expect((await fetch(`${beta}/decisions/${id}`)).status).toBe(404);
  });
});
