import type { ControlConfig } from "../config";
import type { makeRepos } from "../registry/repos";
type Repos = ReturnType<typeof makeRepos>;

export type Route =
  | { kind: "ok"; target: string }
  | { kind: "notFound" } | { kind: "suspended" }
  | { kind: "mismatch" } | { kind: "badHost" };

export function slugFromHost(host: string | undefined, baseDomain: string): string | null {
  if (!host) return null;
  const name = host.split(":")[0];
  const suffix = `.${baseDomain}`;
  if (!name.endsWith(suffix)) return null;
  const label = name.slice(0, -suffix.length);
  if (!label || label.includes(".")) return null; // exactly one label
  return label;
}

export function resolveRoute(repos: Repos, config: ControlConfig, host: string | undefined): Route {
  const slug = slugFromHost(host, config.baseDomain);
  if (!slug) return { kind: "badHost" };
  const t = repos.tenants.get(slug);
  if (!t) return { kind: "notFound" };
  if (t.status === "suspended") return { kind: "suspended" };
  if (t.status === "key-mismatch") return { kind: "mismatch" };
  if (t.status !== "active") return { kind: "notFound" };
  return { kind: "ok", target: `http://${t.containerName}:${t.internalPort}` };
}
