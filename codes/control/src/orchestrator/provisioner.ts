import type { ContainerRuntime } from "./runtime";
import type { ControlConfig } from "../config";
import type { Tenant, makeRepos } from "../registry/repos";
import { fetchFingerprint } from "./fingerprint";
import { validateSlug } from "../slug";

type Repos = ReturnType<typeof makeRepos>;
export interface Provisioner {
  create(slug: string, displayName: string): Promise<{ adminToken: string | null }>;
  suspend(slug: string): Promise<void>;
  resume(slug: string): Promise<void>;
  remove(slug: string, exportPath?: string): Promise<void>;
  targetBaseUrl(t: Tenant): string;
}
export function parseAdminToken(logs: string): string | null {
  const m = /ADMIN TOKEN \(save this, shown once\):\s*(\S+)/.exec(logs);
  return m ? m[1] : null;
}
interface Deps {
  repos: Repos; runtime: ContainerRuntime; config: ControlConfig;
  fetchFp?: (baseUrl: string) => Promise<string>;
  waitHealthy?: (baseUrl: string) => Promise<void>;
}
export function makeProvisioner(deps: Deps): Provisioner {
  const { repos, runtime, config } = deps;
  const fetchFp = deps.fetchFp ?? ((u: string) => fetchFingerprint(u));
  const waitHealthy = deps.waitHealthy ?? defaultWaitHealthy;
  const target = (t: Tenant) => `http://${t.containerName}:${t.internalPort}`;

  return {
    targetBaseUrl: target,
    async create(slug, displayName) {
      validateSlug(slug);
      const t = repos.tenants.create({ slug, displayName }); // throws DuplicateTenantError
      try {
        await runtime.ensureNetwork(config.network);
        await runtime.createVolume(t.volumeName);
        await runtime.run({
          name: t.containerName, image: config.image, network: config.network,
          volume: t.volumeName, mountPath: "/app/data",
          env: { PORT: String(t.internalPort), DATA_DIR: "/app/data" },
          memory: config.tenantMemory, cpus: config.tenantCpus,
        });
        await waitHealthy(target(t));
        repos.tenants.setFingerprint(slug, await fetchFp(target(t)));
        repos.tenants.setStatus(slug, "active");
        return { adminToken: parseAdminToken(await runtime.logs(t.containerName)) };
      } catch (e) {
        // best-effort rollback; leave row in provisioning for operator inspection
        await runtime.remove(t.containerName).catch(() => {});
        throw e;
      }
    },
    async suspend(slug) {
      const t = mustGet(repos, slug);
      await runtime.stop(t.containerName);
      repos.tenants.setStatus(slug, "suspended");
    },
    async resume(slug) {
      const t = mustGet(repos, slug);
      await runtime.start(t.containerName);
      await waitHealthy(target(t));
      const fp = await fetchFp(target(t));
      if (t.keyFingerprint && fp !== t.keyFingerprint) {
        repos.tenants.setStatus(slug, "key-mismatch");
        return;
      }
      repos.tenants.setStatus(slug, "active");
    },
    async remove(slug, exportPath) {
      const t = mustGet(repos, slug);
      repos.tenants.setStatus(slug, "deleting");
      if (exportPath) await runtime.exportVolume(t.volumeName, exportPath);
      await runtime.remove(t.containerName).catch(() => {});
      await runtime.removeVolume(t.volumeName).catch(() => {});
      repos.tenants.remove(slug);
    },
  };
}
function mustGet(repos: Repos, slug: string): Tenant {
  const t = repos.tenants.get(slug);
  if (!t) throw new Error(`unknown tenant '${slug}'`);
  return t;
}
async function defaultWaitHealthy(baseUrl: string): Promise<void> {
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch(`${baseUrl}/health`); if (r.ok) return; } catch { /* retry */ }
    await new Promise((res) => setTimeout(res, 1000));
  }
  throw new Error(`instance at ${baseUrl} never became healthy`);
}
