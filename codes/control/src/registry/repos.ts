import type Database from "better-sqlite3";
import { randomUUID } from "node:crypto";

export type TenantStatus = "provisioning" | "active" | "suspended" | "deleting" | "key-mismatch";
export interface Tenant {
  slug: string; displayName: string; status: TenantStatus;
  containerName: string; volumeName: string; internalPort: number;
  keyFingerprint: string | null; createdAt: number;
}
export class DuplicateTenantError extends Error {
  constructor(slug: string) { super(`tenant '${slug}' already exists`); this.name = "DuplicateTenantError"; }
}
interface Row {
  slug: string; display_name: string; status: TenantStatus;
  container_name: string; volume_name: string; internal_port: number;
  key_fingerprint: string | null; created_at: number;
}
const toTenant = (r: Row): Tenant => ({
  slug: r.slug, displayName: r.display_name, status: r.status,
  containerName: r.container_name, volumeName: r.volume_name, internalPort: r.internal_port,
  keyFingerprint: r.key_fingerprint, createdAt: r.created_at,
});

export interface TenantRepo {
  create(i: { slug: string; displayName: string }): Tenant;
  get(slug: string): Tenant | null;
  list(): Tenant[];
  setStatus(slug: string, status: TenantStatus): void;
  setFingerprint(slug: string, fp: string): void;
  remove(slug: string): void;
}
export interface OperatorRepo {
  create(tokenHash: string): { id: string };
  count(): number;
  findByTokenHash(hash: string): { id: string } | null;
}

export function makeRepos(db: Database.Database): { tenants: TenantRepo; operators: OperatorRepo } {
  const ins = db.prepare(
    `INSERT INTO tenants (slug, display_name, status, container_name, volume_name, internal_port, key_fingerprint, created_at)
     VALUES (@slug,@displayName,@status,@containerName,@volumeName,@internalPort,@keyFingerprint,@createdAt)`,
  );
  const getOne = db.prepare(`SELECT * FROM tenants WHERE slug = ?`);
  const all = db.prepare(`SELECT * FROM tenants ORDER BY created_at ASC, slug ASC`);
  const setStatus = db.prepare(`UPDATE tenants SET status = ? WHERE slug = ?`);
  const setFp = db.prepare(`UPDATE tenants SET key_fingerprint = ? WHERE slug = ?`);
  const del = db.prepare(`DELETE FROM tenants WHERE slug = ?`);

  const tenants: TenantRepo = {
    create({ slug, displayName }) {
      const t: Tenant = {
        slug, displayName, status: "provisioning",
        containerName: `tessera-${slug}`, volumeName: `tessera-${slug}`,
        internalPort: 3001, keyFingerprint: null, createdAt: Date.now(),
      };
      try { ins.run(t); } catch (e) {
        if ((e as { code?: string }).code === "SQLITE_CONSTRAINT_PRIMARYKEY")
          throw new DuplicateTenantError(slug);
        throw e;
      }
      return t;
    },
    get(slug) { const r = getOne.get(slug) as Row | undefined; return r ? toTenant(r) : null; },
    list() { return (all.all() as Row[]).map(toTenant); },
    setStatus(slug, status) { setStatus.run(status, slug); },
    setFingerprint(slug, fp) { setFp.run(fp, slug); },
    remove(slug) { del.run(slug); },
  };
  const insOp = db.prepare(`INSERT INTO operator_admins (id, token_hash, created_at) VALUES (?,?,?)`);
  const cntOp = db.prepare(`SELECT COUNT(*) AS c FROM operator_admins`);
  const byHash = db.prepare(`SELECT id FROM operator_admins WHERE token_hash = ?`);
  const operators: OperatorRepo = {
    create(tokenHash) { const id = randomUUID(); insOp.run(id, tokenHash, Date.now()); return { id }; },
    count() { return (cntOp.get() as { c: number }).c; },
    findByTokenHash(hash) { return (byHash.get(hash) as { id: string } | undefined) ?? null; },
  };
  return { tenants, operators };
}
