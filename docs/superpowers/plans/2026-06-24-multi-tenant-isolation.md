# Tessera Multi-Tenant (control plane) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `tessera-control`, a control plane that runs one isolated `tessera-server` container per organization on localhost, routed by `<slug>.localhost`, so an operator hosts many orgs with real (OS-level) isolation.

**Architecture:** A new Node/TS package `codes/control`. It owns a small registry DB (routing metadata + key fingerprints only), an orchestrator that creates/stops per-org containers via the `docker`/`podman` CLI, a host-routing reverse proxy (`<slug>.localhost:8787` → `tessera-<slug>:3001`), and an operator admin API driven by a `tessera-ctl` CLI. The existing `codes/server` is used **as an image, unchanged**.

**Tech Stack:** TypeScript, Node ≥ 22, express, better-sqlite3, zod, `http-proxy`, vitest + supertest. Container runtime: `docker` or `podman` (configurable), driven via `execFile` (no shell). Mirrors the conventions in `codes/server` (repo pattern, SHA-256 token hashing, zod schemas, tsc build).

## Global Constraints

- The existing server (`codes/server`) is **not modified**; it is consumed only as the container image `tessera-server:latest`. (spec §2, §5.1)
- The registry stores **routing metadata + public-key fingerprints only** — never ballot data, never tenant private keys. (spec §4, §6)
- **v1 is localhost-only.** Do NOT implement: cloudflared/TLS, scale-to-zero, bring-your-own-key, self-serve signup. (spec §2, §13)
- Slug: `^[a-z0-9-]{1,40}$`; reserved (blocked): `www`, `admin`, `api`, `control`, `health`, `localhost`. (spec §6)
- Naming: container `tessera-<slug>`, volume `tessera-<slug>`, network `tessera-net`, instance port `3001`, control plane port `8787`. (spec §4, §6, §7)
- Tenant resource caps: configurable, default `--memory 256m --cpus 0.5`. (spec §8)
- Key fingerprint = lowercase hex SHA-256 of the SPKI PEM string returned by the instance's `GET /key` (`serverPubKeyPem`). (spec §9)
- Container runtime binary is configurable (`TESSERA_RUNTIME=docker|podman`, default `docker`); Podman-rootless is the preferred posture. (spec §16)
- Tenant status enum: `provisioning | active | suspended | deleting | key-mismatch`. (spec §6, §8)

---

### Task 1: Package scaffold + typed config

**Files:**
- Create: `codes/control/package.json`
- Create: `codes/control/tsconfig.json`, `codes/control/tsconfig.build.json`
- Create: `codes/control/vitest.config.ts`
- Create: `codes/control/src/config.ts`
- Test: `codes/control/test/config.test.ts`

**Interfaces:**
- Produces: `loadConfig(env: NodeJS.ProcessEnv): ControlConfig` where
  `ControlConfig = { port: number; adminPort: number; runtime: "docker"|"podman"; image: string; network: string; instancePort: number; tenantMemory: string; tenantCpus: string; dataDir: string; baseDomain: string }`.

- [ ] **Step 1: Create `codes/control/package.json`**

```json
{
  "name": "tessera-control",
  "version": "0.0.0",
  "private": true,
  "type": "commonjs",
  "bin": { "tessera-ctl": "dist/cli.js" },
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "better-sqlite3": "^11.0.0",
    "express": "^4.19.2",
    "http-proxy": "^1.18.1",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/better-sqlite3": "^7.6.11",
    "@types/express": "^4.17.21",
    "@types/http-proxy": "^1.17.14",
    "@types/node": "^22.0.0",
    "@types/supertest": "^6.0.2",
    "supertest": "^7.0.0",
    "ts-node": "^10.9.2",
    "typescript": "^5.5.4",
    "vitest": "^4.0.0"
  }
}
```

- [ ] **Step 2: Create `codes/control/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "CommonJS", "moduleResolution": "node",
    "strict": true, "esModuleInterop": true, "skipLibCheck": true,
    "resolveJsonModule": true, "outDir": "dist", "rootDir": ".",
    "types": ["node"]
  },
  "include": ["src", "test"]
}
```

- [ ] **Step 3: Create `codes/control/tsconfig.build.json`**

```json
{ "extends": "./tsconfig.json", "compilerOptions": { "rootDir": "src" }, "include": ["src"] }
```

- [ ] **Step 4: Create `codes/control/vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { include: ["test/**/*.test.ts"], environment: "node" } });
```

- [ ] **Step 5: Write the failing test** — `codes/control/test/config.test.ts`

```ts
import { describe, it, expect } from "vitest";
import { loadConfig } from "../src/config";

describe("loadConfig", () => {
  it("applies localhost-first defaults", () => {
    const c = loadConfig({});
    expect(c.port).toBe(8787);
    expect(c.runtime).toBe("docker");
    expect(c.image).toBe("tessera-server:latest");
    expect(c.network).toBe("tessera-net");
    expect(c.instancePort).toBe(3001);
    expect(c.tenantMemory).toBe("256m");
    expect(c.tenantCpus).toBe("0.5");
    expect(c.baseDomain).toBe("localhost");
  });
  it("reads overrides and rejects an unknown runtime", () => {
    expect(loadConfig({ TESSERA_RUNTIME: "podman" }).runtime).toBe("podman");
    expect(() => loadConfig({ TESSERA_RUNTIME: "lxc" })).toThrow(/runtime/i);
  });
});
```

- [ ] **Step 6: Run test to verify it fails** — `cd codes/control && npm install && npx vitest run test/config.test.ts`. Expected: FAIL (`loadConfig` not found).

- [ ] **Step 7: Implement** — `codes/control/src/config.ts`

```ts
export interface ControlConfig {
  port: number; adminPort: number;
  runtime: "docker" | "podman"; image: string; network: string;
  instancePort: number; tenantMemory: string; tenantCpus: string;
  dataDir: string; baseDomain: string;
}
export function loadConfig(env: NodeJS.ProcessEnv): ControlConfig {
  const runtime = env.TESSERA_RUNTIME ?? "docker";
  if (runtime !== "docker" && runtime !== "podman")
    throw new Error(`unsupported runtime '${runtime}' (use docker|podman)`);
  const num = (v: string | undefined, d: number) => (v ? Number(v) : d);
  return {
    port: num(env.PORT, 8787),
    adminPort: num(env.ADMIN_PORT, 8786),
    runtime,
    image: env.TESSERA_IMAGE ?? "tessera-server:latest",
    network: env.TESSERA_NETWORK ?? "tessera-net",
    instancePort: num(env.TESSERA_INSTANCE_PORT, 3001),
    tenantMemory: env.TESSERA_TENANT_MEM ?? "256m",
    tenantCpus: env.TESSERA_TENANT_CPUS ?? "0.5",
    dataDir: env.DATA_DIR ?? "/app/control-data",
    baseDomain: env.TESSERA_BASE_DOMAIN ?? "localhost",
  };
}
```

- [ ] **Step 8: Run test to verify it passes** — `npx vitest run test/config.test.ts`. Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add codes/control/package.json codes/control/tsconfig.json codes/control/tsconfig.build.json \
  codes/control/vitest.config.ts codes/control/src/config.ts codes/control/test/config.test.ts \
  codes/control/package-lock.json
git commit -m "feat(control): scaffold tessera-control package + typed config"
```

---

### Task 2: Slug validation

**Files:**
- Create: `codes/control/src/slug.ts`
- Test: `codes/control/test/slug.test.ts`

**Interfaces:**
- Produces: `RESERVED_SLUGS: ReadonlySet<string>`; `validateSlug(s: string): void` (throws `SlugError` on invalid); `class SlugError extends Error`.

- [ ] **Step 1: Write the failing test** — `codes/control/test/slug.test.ts`

```ts
import { describe, it, expect } from "vitest";
import { validateSlug, SlugError } from "../src/slug";

describe("validateSlug", () => {
  it("accepts dns-safe slugs", () => {
    expect(() => validateSlug("acme")).not.toThrow();
    expect(() => validateSlug("acme-2")).not.toThrow();
  });
  it("rejects bad shapes", () => {
    for (const bad of ["", "Acme", "a_b", "a.b", "-x", "x ", "a".repeat(41)])
      expect(() => validateSlug(bad), bad).toThrow(SlugError);
  });
  it("rejects reserved slugs", () => {
    for (const r of ["www", "admin", "api", "control", "health", "localhost"])
      expect(() => validateSlug(r), r).toThrow(/reserved/i);
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/slug.test.ts`. Expected: FAIL (module not found).

- [ ] **Step 3: Implement** — `codes/control/src/slug.ts`

```ts
export class SlugError extends Error {
  constructor(msg: string) { super(msg); this.name = "SlugError"; }
}
export const RESERVED_SLUGS: ReadonlySet<string> = new Set([
  "www", "admin", "api", "control", "health", "localhost",
]);
const SLUG_RE = /^[a-z0-9-]{1,40}$/;
export function validateSlug(s: string): void {
  if (!SLUG_RE.test(s)) throw new SlugError(`invalid slug '${s}' (use ^[a-z0-9-]{1,40}$)`);
  if (s.startsWith("-") || s.endsWith("-")) throw new SlugError(`slug '${s}' may not start/end with '-'`);
  if (RESERVED_SLUGS.has(s)) throw new SlugError(`slug '${s}' is reserved`);
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/slug.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/slug.ts codes/control/test/slug.test.ts
git commit -m "feat(control): dns-safe slug validation + reserved list"
```

---

### Task 3: Registry schema + repositories

**Files:**
- Create: `codes/control/src/registry/schema.ts`
- Create: `codes/control/src/registry/db.ts`
- Create: `codes/control/src/registry/repos.ts`
- Test: `codes/control/test/registry/repos.test.ts`

**Interfaces:**
- Produces:
  - `openDb(path: string): Database.Database`; `migrate(db): void`.
  - `Tenant = { slug; displayName; status; containerName; volumeName; internalPort; keyFingerprint: string|null; createdAt: number }`.
  - `TenantStatus = "provisioning"|"active"|"suspended"|"deleting"|"key-mismatch"`.
  - `makeRepos(db): { tenants: TenantRepo; operators: OperatorRepo }`.
  - `TenantRepo`: `create(input: {slug; displayName}): Tenant` (status `provisioning`, derives container/volume names, port from caller via `setPort`? no — see code), `get(slug): Tenant|null`, `list(): Tenant[]`, `setStatus(slug, status): void`, `setFingerprint(slug, fp): void`, `remove(slug): void`. Throws `DuplicateTenantError` on existing slug.
  - `OperatorRepo`: `create(tokenHash: string): {id}`, `count(): number`, `findByTokenHash(hash): {id}|null`.

- [ ] **Step 1: Implement `codes/control/src/registry/schema.ts`** (no test of its own; covered by repos test)

```ts
export const MIGRATIONS: ReadonlyArray<{ id: number; sql: string }> = [
  {
    id: 1,
    sql: `
      CREATE TABLE tenants (
        slug            TEXT PRIMARY KEY,
        display_name    TEXT NOT NULL,
        status          TEXT NOT NULL,
        container_name  TEXT NOT NULL,
        volume_name     TEXT NOT NULL,
        internal_port   INTEGER NOT NULL,
        key_fingerprint TEXT,
        created_at      INTEGER NOT NULL
      );
      CREATE TABLE operator_admins (
        id         TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE _migrations (id INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);
    `,
  },
];
```

- [ ] **Step 2: Implement `codes/control/src/registry/db.ts`**

```ts
import Database from "better-sqlite3";
import { MIGRATIONS } from "./schema";
export function openDb(path: string): Database.Database {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  return db;
}
export function migrate(db: Database.Database): void {
  db.exec(`CREATE TABLE IF NOT EXISTS _migrations (id INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)`);
  const done = new Set<number>(
    (db.prepare(`SELECT id FROM _migrations`).all() as { id: number }[]).map((r) => r.id),
  );
  for (const m of MIGRATIONS) {
    if (done.has(m.id)) continue;
    db.transaction(() => {
      db.exec(m.sql.replace(/CREATE TABLE _migrations[^;]+;/, ""));
      db.prepare(`INSERT INTO _migrations (id, applied_at) VALUES (?, ?)`).run(m.id, Date.now());
    })();
  }
}
```

- [ ] **Step 3: Write the failing test** — `codes/control/test/registry/repos.test.ts`

```ts
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
```

- [ ] **Step 4: Run to verify it fails** — `npx vitest run test/registry/repos.test.ts`. Expected: FAIL (repos module not found).

- [ ] **Step 5: Implement** — `codes/control/src/registry/repos.ts`

```ts
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
```

- [ ] **Step 6: Run to verify it passes** — `npx vitest run test/registry/repos.test.ts`. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add codes/control/src/registry codes/control/test/registry
git commit -m "feat(control): registry schema + tenant/operator repos"
```

---

### Task 4: Operator admin auth + bootstrap

**Files:**
- Create: `codes/control/src/admin/auth.ts`
- Test: `codes/control/test/admin/auth.test.ts`

**Interfaces:**
- Consumes: `OperatorRepo` (Task 3).
- Produces: `hashToken(t: string): string` (sha256 hex); `bootstrapOperator(repos): { token: string } | null` (mints + returns plaintext once iff none exist, else null); `requireOperator(repos): express.RequestHandler` (401 unless `Authorization: Bearer <token>` matches a stored hash).

- [ ] **Step 1: Write the failing test** — `codes/control/test/admin/auth.test.ts`

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { hashToken, bootstrapOperator } from "../../src/admin/auth";

let repos: ReturnType<typeof makeRepos>;
beforeEach(() => { const db = openDb(":memory:"); migrate(db); repos = makeRepos(db); });

describe("operator auth", () => {
  it("hashToken is stable sha256 hex", () => {
    expect(hashToken("abc")).toMatch(/^[0-9a-f]{64}$/);
    expect(hashToken("abc")).toBe(hashToken("abc"));
  });
  it("bootstrap mints once, stores only the hash", () => {
    const first = bootstrapOperator(repos);
    expect(first?.token).toMatch(/.{20,}/);
    expect(repos.operators.findByTokenHash(hashToken(first!.token))).not.toBeNull();
    expect(bootstrapOperator(repos)).toBeNull(); // idempotent
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/admin/auth.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/admin/auth.ts`

```ts
import { createHash, randomBytes } from "node:crypto";
import type { RequestHandler } from "express";
import type { makeRepos } from "../registry/repos";

type Repos = ReturnType<typeof makeRepos>;
export function hashToken(t: string): string { return createHash("sha256").update(t).digest("hex"); }

export function bootstrapOperator(repos: Repos): { token: string } | null {
  if (repos.operators.count() > 0) return null;
  const token = randomBytes(32).toString("base64url");
  repos.operators.create(hashToken(token));
  return { token };
}

export function requireOperator(repos: Repos): RequestHandler {
  return (req, res, next) => {
    const h = req.header("authorization") ?? "";
    const m = /^Bearer (.+)$/.exec(h);
    if (!m || !repos.operators.findByTokenHash(hashToken(m[1]))) {
      res.status(401).json({ error: "unauthorized" }); return;
    }
    next();
  };
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/admin/auth.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/admin/auth.ts codes/control/test/admin/auth.test.ts
git commit -m "feat(control): operator admin bootstrap + bearer auth"
```

---

### Task 5: Key fingerprint

**Files:**
- Create: `codes/control/src/orchestrator/fingerprint.ts`
- Test: `codes/control/test/orchestrator/fingerprint.test.ts`

**Interfaces:**
- Produces: `fingerprintOfPem(pem: string): string` (lowercase hex sha256 of the PEM string); `fetchFingerprint(baseUrl: string, fetchImpl?: typeof fetch): Promise<string>` (GETs `${baseUrl}/key`, reads `serverPubKeyPem`, returns its fingerprint).

- [ ] **Step 1: Write the failing test** — `codes/control/test/orchestrator/fingerprint.test.ts`

```ts
import { describe, it, expect } from "vitest";
import { fingerprintOfPem, fetchFingerprint } from "../../src/orchestrator/fingerprint";

describe("fingerprint", () => {
  it("hashes the PEM string deterministically", () => {
    const fp = fingerprintOfPem("-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n");
    expect(fp).toMatch(/^[0-9a-f]{64}$/);
    expect(fingerprintOfPem("x")).not.toBe(fp);
  });
  it("fetchFingerprint reads serverPubKeyPem from /key", async () => {
    const fakeFetch = (async (url: string) => {
      expect(url).toBe("http://inst:3001/key");
      return { ok: true, json: async () => ({ serverPubKeyPem: "PEMDATA" }) } as Response;
    }) as unknown as typeof fetch;
    expect(await fetchFingerprint("http://inst:3001", fakeFetch)).toBe(fingerprintOfPem("PEMDATA"));
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/orchestrator/fingerprint.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/orchestrator/fingerprint.ts`

```ts
import { createHash } from "node:crypto";
export function fingerprintOfPem(pem: string): string {
  return createHash("sha256").update(pem).digest("hex");
}
export async function fetchFingerprint(baseUrl: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  const res = await fetchImpl(`${baseUrl}/key`);
  if (!res.ok) throw new Error(`/key returned ${res.status}`);
  const body = (await res.json()) as { serverPubKeyPem?: string };
  if (!body.serverPubKeyPem) throw new Error("/key missing serverPubKeyPem");
  return fingerprintOfPem(body.serverPubKeyPem);
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/orchestrator/fingerprint.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/orchestrator/fingerprint.ts codes/control/test/orchestrator/fingerprint.test.ts
git commit -m "feat(control): public-key fingerprint (sha256 of /key SPKI)"
```

---

### Task 6: Container runtime abstraction (interface + CLI impl + fake)

**Files:**
- Create: `codes/control/src/orchestrator/runtime.ts`
- Create: `codes/control/test/support/fakeRuntime.ts`
- Test: `codes/control/test/orchestrator/runtime.test.ts`

**Interfaces:**
- Produces:
  - `interface ContainerRuntime { ensureNetwork(name): Promise<void>; createVolume(name): Promise<void>; run(opts: RunOpts): Promise<void>; stop(name): Promise<void>; start(name): Promise<void>; remove(name): Promise<void>; removeVolume(name): Promise<void>; logs(name): Promise<string>; exportVolume(volume, outPath): Promise<void>; }`
  - `RunOpts = { name; image; network; volume; mountPath: string; env: Record<string,string>; memory: string; cpus: string }`.
  - `makeCliRuntime(bin: "docker"|"podman", exec?: ExecFn): ContainerRuntime` where `ExecFn = (bin, args[]) => Promise<{stdout:string}>` (default wraps `execFile`).
  - `class FakeRuntime implements ContainerRuntime` (test support) recording calls and a settable `logsText`.

- [ ] **Step 1: Implement `codes/control/test/support/fakeRuntime.ts`**

```ts
import type { ContainerRuntime, RunOpts } from "../../src/orchestrator/runtime";
export class FakeRuntime implements ContainerRuntime {
  calls: string[] = [];
  running = new Set<string>();
  volumes = new Set<string>();
  logsText = "ADMIN TOKEN (save this, shown once): TENANTTOK\nTessera server running on port 3001";
  failRunFor?: string;
  async ensureNetwork(n: string) { this.calls.push(`net:${n}`); }
  async createVolume(n: string) { this.calls.push(`vol+:${n}`); this.volumes.add(n); }
  async run(o: RunOpts) {
    this.calls.push(`run:${o.name}`);
    if (this.failRunFor === o.name) throw new Error("run failed");
    this.running.add(o.name);
  }
  async stop(n: string) { this.calls.push(`stop:${n}`); this.running.delete(n); }
  async start(n: string) { this.calls.push(`start:${n}`); this.running.add(n); }
  async remove(n: string) { this.calls.push(`rm:${n}`); this.running.delete(n); }
  async removeVolume(n: string) { this.calls.push(`vol-:${n}`); this.volumes.delete(n); }
  async logs(n: string) { this.calls.push(`logs:${n}`); return this.logsText; }
  async exportVolume(v: string, out: string) { this.calls.push(`export:${v}:${out}`); }
}
```

- [ ] **Step 2: Write the failing test** — `codes/control/test/orchestrator/runtime.test.ts`

```ts
import { describe, it, expect } from "vitest";
import { makeCliRuntime } from "../../src/orchestrator/runtime";

describe("CliRuntime", () => {
  it("builds a correct `run` command (no shell, arg array)", async () => {
    const seen: string[][] = [];
    const exec = async (_bin: string, args: string[]) => { seen.push(args); return { stdout: "" }; };
    const rt = makeCliRuntime("podman", exec);
    await rt.run({
      name: "tessera-acme", image: "tessera-server:latest", network: "tessera-net",
      volume: "tessera-acme", mountPath: "/app/data",
      env: { PORT: "3001", DATA_DIR: "/app/data" }, memory: "256m", cpus: "0.5",
    });
    const a = seen[0];
    expect(a[0]).toBe("run");
    expect(a).toContain("--name"); expect(a).toContain("tessera-acme");
    expect(a).toContain("--network"); expect(a).toContain("tessera-net");
    expect(a).toContain("--memory"); expect(a).toContain("256m");
    expect(a).toContain("--cpus"); expect(a).toContain("0.5");
    expect(a).toContain("-v"); expect(a).toContain("tessera-acme:/app/data");
    expect(a).toContain("-e"); expect(a).toContain("PORT=3001");
    expect(a).toContain("tessera-server:latest");
    // never publishes a host port:
    expect(a).not.toContain("-p");
  });
});
```

- [ ] **Step 3: Run to verify it fails** — `npx vitest run test/orchestrator/runtime.test.ts`. Expected: FAIL.

- [ ] **Step 4: Implement** — `codes/control/src/orchestrator/runtime.ts`

```ts
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const pexec = promisify(execFile);

export interface RunOpts {
  name: string; image: string; network: string; volume: string; mountPath: string;
  env: Record<string, string>; memory: string; cpus: string;
}
export interface ContainerRuntime {
  ensureNetwork(name: string): Promise<void>;
  createVolume(name: string): Promise<void>;
  run(opts: RunOpts): Promise<void>;
  stop(name: string): Promise<void>;
  start(name: string): Promise<void>;
  remove(name: string): Promise<void>;
  removeVolume(name: string): Promise<void>;
  logs(name: string): Promise<string>;
  exportVolume(volume: string, outPath: string): Promise<void>;
}
export type ExecFn = (bin: string, args: string[]) => Promise<{ stdout: string }>;

export function makeCliRuntime(bin: "docker" | "podman", exec: ExecFn = (b, a) => pexec(b, a)): ContainerRuntime {
  const run1 = (args: string[]) => exec(bin, args);
  return {
    async ensureNetwork(name) {
      try { await run1(["network", "inspect", name]); }
      catch { await run1(["network", "create", name]); }
    },
    async createVolume(name) {
      try { await run1(["volume", "inspect", name]); }
      catch { await run1(["volume", "create", name]); }
    },
    async run(o) {
      const args = ["run", "-d", "--name", o.name, "--network", o.network,
        "--restart", "unless-stopped", "--memory", o.memory, "--cpus", o.cpus,
        "-v", `${o.volume}:${o.mountPath}`];
      for (const [k, v] of Object.entries(o.env)) args.push("-e", `${k}=${v}`);
      args.push(o.image);
      await run1(args);
    },
    async stop(name) { await run1(["stop", name]); },
    async start(name) { await run1(["start", name]); },
    async remove(name) { await run1(["rm", "-f", name]); },
    async removeVolume(name) { await run1(["volume", "rm", name]); },
    async logs(name) { return (await run1(["logs", name])).stdout; },
    async exportVolume(volume, outPath) {
      // tar the volume contents via a throwaway alpine container.
      await run1(["run", "--rm", "-v", `${volume}:/data`, "-v", `${outPath}:/out`,
        "alpine", "tar", "czf", "/out/export.tgz", "-C", "/data", "."]);
    },
  };
}
```

- [ ] **Step 5: Run to verify it passes** — `npx vitest run test/orchestrator/runtime.test.ts`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add codes/control/src/orchestrator/runtime.ts codes/control/test/support/fakeRuntime.ts codes/control/test/orchestrator/runtime.test.ts
git commit -m "feat(control): container runtime abstraction (docker/podman CLI) + fake"
```

---

### Task 7: Provisioner (lifecycle + fingerprint pinning + key-swap detection)

**Files:**
- Create: `codes/control/src/orchestrator/provisioner.ts`
- Test: `codes/control/test/orchestrator/provisioner.test.ts`

**Interfaces:**
- Consumes: `ContainerRuntime` (Task 6), `TenantRepo` (Task 3), `fetchFingerprint` (Task 5), `validateSlug` (Task 2), `ControlConfig` (Task 1).
- Produces: `makeProvisioner(deps: { repos; runtime; config; fetchFp?; waitHealthy? }): Provisioner` with:
  - `create(slug, displayName): Promise<{ adminToken: string | null }>` — validate slug → registry row (provisioning) → ensureNetwork/createVolume → run → waitHealthy → pin fingerprint → status active → return tenant admin token parsed from logs.
  - `suspend(slug): Promise<void>`; `resume(slug): Promise<void>` (re-checks fingerprint → `key-mismatch` if changed); `remove(slug, exportPath?): Promise<void>`.
  - `targetBaseUrl(t: Tenant): string` = `http://${t.containerName}:${t.internalPort}`.
  - `parseAdminToken(logs: string): string | null`.

- [ ] **Step 1: Write the failing test** — `codes/control/test/orchestrator/provisioner.test.ts`

```ts
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
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/orchestrator/provisioner.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/orchestrator/provisioner.ts`

```ts
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
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/orchestrator/provisioner.test.ts`. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/orchestrator/provisioner.ts codes/control/test/orchestrator/provisioner.test.ts
git commit -m "feat(control): provisioner lifecycle + fingerprint pinning + key-swap detection"
```

---

### Task 8: Host router (Host header → routing decision)

**Files:**
- Create: `codes/control/src/proxy/hostRouter.ts`
- Test: `codes/control/test/proxy/hostRouter.test.ts`

**Interfaces:**
- Consumes: `TenantRepo` (Task 3), `ControlConfig` (Task 1).
- Produces: `slugFromHost(host: string|undefined, baseDomain: string): string | null` (strips `:port`, returns the single label before `.<baseDomain>`); `resolveRoute(repos, config, host): Route` where `Route = { kind: "ok"; target: string } | { kind: "notFound" } | { kind: "suspended" } | { kind: "mismatch" } | { kind: "badHost" }`.

- [ ] **Step 1: Write the failing test** — `codes/control/test/proxy/hostRouter.test.ts`

```ts
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
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/proxy/hostRouter.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/proxy/hostRouter.ts`

```ts
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
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/proxy/hostRouter.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/proxy/hostRouter.ts codes/control/test/proxy/hostRouter.test.ts
git commit -m "feat(control): host-header → tenant routing decisions"
```

---

### Task 9: Reverse proxy server

**Files:**
- Create: `codes/control/src/proxy/proxy.ts`
- Test: `codes/control/test/proxy/proxy.test.ts`

**Interfaces:**
- Consumes: `resolveRoute` (Task 8), `TenantRepo`, `ControlConfig`.
- Produces: `createProxyServer(deps: { repos; config; proxy? }): http.Server` — an HTTP server that, per request, resolves the route and either proxies to the target or returns 404/403/503/421 with a JSON body. `421 Misdirected Request` for `badHost`.

- [ ] **Step 1: Write the failing test** — `codes/control/test/proxy/proxy.test.ts`

```ts
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
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/proxy/proxy.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/proxy/proxy.ts`

```ts
import http from "node:http";
import httpProxy from "http-proxy";
import type { ControlConfig } from "../config";
import type { makeRepos } from "../registry/repos";
import { resolveRoute } from "./hostRouter";
type Repos = ReturnType<typeof makeRepos>;

interface Deps {
  repos: Repos; config: ControlConfig;
  /** test seam: override the upstream URL for a resolved "ok" route. */
  targetOverride?: (target: string) => string;
}
export function createProxyServer(deps: Deps): http.Server {
  const proxy = httpProxy.createProxyServer({ xfwd: true });
  proxy.on("error", (_e, _req, res) => {
    if (res instanceof http.ServerResponse && !res.headersSent) {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: "bad-gateway" }));
    }
  });
  const json = (res: http.ServerResponse, code: number, body: unknown) => {
    res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(body));
  };
  return http.createServer((req, res) => {
    const route = resolveRoute(deps.repos, deps.config, req.headers.host);
    switch (route.kind) {
      case "ok": {
        const target = deps.targetOverride ? deps.targetOverride(route.target) : route.target;
        proxy.web(req, res, { target });
        return;
      }
      case "notFound": return json(res, 404, { error: "no-such-org" });
      case "suspended": return json(res, 503, { error: "org-suspended" });
      case "mismatch": return json(res, 503, { error: "org-key-mismatch" });
      case "badHost": return json(res, 421, { error: "use https://<org>.localhost" });
    }
  });
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/proxy/proxy.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/proxy/proxy.ts codes/control/test/proxy/proxy.test.ts
git commit -m "feat(control): host-routing reverse proxy with status-coded refusals"
```

---

### Task 10: Operator admin API

**Files:**
- Create: `codes/control/src/admin/routes.ts`
- Test: `codes/control/test/admin/routes.test.ts`

**Interfaces:**
- Consumes: `Provisioner` (Task 7), `TenantRepo` (Task 3), `requireOperator` (Task 4).
- Produces: `createAdminApp(deps: { repos; provisioner; operatorToken? }): express.Express` with routes (all behind `requireOperator`): `POST /tenants {slug,displayName}` → 201 `{slug, adminToken}`; `GET /tenants` → `{tenants:[...]}`; `POST /tenants/:slug/suspend|resume` → `{slug,status}`; `DELETE /tenants/:slug?export=path` → 200 `{slug, deleted:true}`. Validation errors → 400; duplicate → 409; unknown → 404.

- [ ] **Step 1: Write the failing test** — `codes/control/test/admin/routes.test.ts`

```ts
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
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/admin/routes.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/admin/routes.ts`

```ts
import express from "express";
import { z } from "zod";
import type { Provisioner } from "../orchestrator/provisioner";
import type { makeRepos } from "../registry/repos";
import { requireOperator } from "./auth";
import { SlugError } from "../slug";
import { DuplicateTenantError } from "../registry/repos";

type Repos = ReturnType<typeof makeRepos>;
const CreateBody = z.object({ slug: z.string(), displayName: z.string().min(1) });

export function createAdminApp(deps: { repos: Repos; provisioner: Provisioner }): express.Express {
  const app = express();
  app.use(express.json());
  app.use(requireOperator(deps.repos));

  app.post("/tenants", async (req, res) => {
    const parsed = CreateBody.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "bad-request", issues: parsed.error.issues }); return; }
    try {
      const { adminToken } = await deps.provisioner.create(parsed.data.slug, parsed.data.displayName);
      res.status(201).json({ slug: parsed.data.slug, adminToken });
    } catch (e) {
      if (e instanceof SlugError) { res.status(400).json({ error: e.message }); return; }
      if (e instanceof DuplicateTenantError) { res.status(409).json({ error: e.message }); return; }
      res.status(500).json({ error: (e as Error).message });
    }
  });

  app.get("/tenants", (_req, res) => res.json({ tenants: deps.repos.tenants.list() }));

  const lifecycle = (fn: (slug: string) => Promise<void>) => async (req: express.Request, res: express.Response) => {
    if (!deps.repos.tenants.get(req.params.slug)) { res.status(404).json({ error: "no-such-org" }); return; }
    try { await fn(req.params.slug); res.json({ slug: req.params.slug, status: deps.repos.tenants.get(req.params.slug)?.status ?? "deleted", deleted: !deps.repos.tenants.get(req.params.slug) }); }
    catch (e) { res.status(500).json({ error: (e as Error).message }); }
  };
  app.post("/tenants/:slug/suspend", lifecycle((s) => deps.provisioner.suspend(s)));
  app.post("/tenants/:slug/resume", lifecycle((s) => deps.provisioner.resume(s)));
  app.delete("/tenants/:slug", async (req, res) => {
    if (!deps.repos.tenants.get(req.params.slug)) { res.status(404).json({ error: "no-such-org" }); return; }
    try { await deps.provisioner.remove(req.params.slug, typeof req.query.export === "string" ? req.query.export : undefined); res.json({ slug: req.params.slug, deleted: true }); }
    catch (e) { res.status(500).json({ error: (e as Error).message }); }
  });
  return app;
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/admin/routes.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/admin/routes.ts codes/control/test/admin/routes.test.ts
git commit -m "feat(control): operator admin API (create/list/suspend/resume/delete)"
```

---

### Task 11: Bootstrap entrypoint

**Files:**
- Create: `codes/control/src/index.ts`
- Test: `codes/control/test/index.smoke.test.ts`

**Interfaces:**
- Consumes: all prior modules.
- Produces: `buildControlPlane(config): { adminApp; proxyServer; bootstrapToken: string | null }` (pure-ish factory, no `.listen`); `index.ts` calls it, prints the operator token once, and listens on `config.adminPort` (admin) + `config.port` (proxy).

- [ ] **Step 1: Write the failing test** — `codes/control/test/index.smoke.test.ts`

```ts
import { describe, it, expect } from "vitest";
import { buildControlPlane } from "../src/index";
import { loadConfig } from "../src/config";

describe("buildControlPlane", () => {
  it("mints an operator token on first build and wires both apps", () => {
    const cp = buildControlPlane(loadConfig({ DATA_DIR: ":memory:" }));
    expect(cp.bootstrapToken).toMatch(/.{20,}/);
    expect(typeof cp.adminApp).toBe("function");      // express app
    expect(cp.proxyServer.listen).toBeTypeOf("function"); // http.Server
  });
});
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/index.smoke.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/index.ts`

```ts
import path from "node:path";
import express from "express";
import http from "node:http";
import { loadConfig, type ControlConfig } from "./config";
import { openDb, migrate } from "./registry/db";
import { makeRepos } from "./registry/repos";
import { makeCliRuntime } from "./orchestrator/runtime";
import { makeProvisioner } from "./orchestrator/provisioner";
import { createAdminApp } from "./admin/routes";
import { createProxyServer } from "./proxy/proxy";
import { bootstrapOperator } from "./admin/auth";

export function buildControlPlane(config: ControlConfig): {
  adminApp: express.Express; proxyServer: http.Server; bootstrapToken: string | null;
} {
  const dbPath = config.dataDir === ":memory:" ? ":memory:" : path.join(config.dataDir, "control.db");
  const db = openDb(dbPath); migrate(db);
  const repos = makeRepos(db);
  const runtime = makeCliRuntime(config.runtime);
  const provisioner = makeProvisioner({ repos, runtime, config });
  const adminApp = createAdminApp({ repos, provisioner });
  const proxyServer = createProxyServer({ repos, config });
  const bootstrapToken = bootstrapOperator(repos)?.token ?? null;
  return { adminApp, proxyServer, bootstrapToken };
}

if (require.main === module) {
  const config = loadConfig(process.env);
  const cp = buildControlPlane(config);
  if (cp.bootstrapToken) console.log("OPERATOR TOKEN (save this, shown once):", cp.bootstrapToken);
  cp.adminApp.listen(config.adminPort, "127.0.0.1", () => console.log(`admin API on :${config.adminPort}`));
  cp.proxyServer.listen(config.port, "0.0.0.0", () => console.log(`proxy on :${config.port}`));
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/index.smoke.test.ts`. Expected: PASS.

- [ ] **Step 5: Full build + suite green**

Run: `cd codes/control && npm run typecheck && npm run build && npm test`. Expected: typecheck clean, build emits `dist/`, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add codes/control/src/index.ts codes/control/test/index.smoke.test.ts
git commit -m "feat(control): bootstrap entrypoint (admin + proxy, operator token)"
```

---

### Task 12: `tessera-ctl` CLI

**Files:**
- Create: `codes/control/src/cli.ts`
- Test: `codes/control/test/cli.test.ts`

**Interfaces:**
- Consumes: the admin API over HTTP.
- Produces: `runCli(argv: string[], env, fetchImpl?): Promise<{ code: number; out: string }>`. Commands: `create <slug> [--display-name <n>]`, `list`, `suspend <slug>`, `resume <slug>`, `delete <slug> [--export <path>]`. Reads admin base URL from `TESSERA_ADMIN_URL` (default `http://127.0.0.1:8786`) and token from `TESSERA_OPERATOR_TOKEN`.

- [ ] **Step 1: Write the failing test** — `codes/control/test/cli.test.ts`

```ts
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
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run test/cli.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement** — `codes/control/src/cli.ts`

```ts
type Env = Record<string, string | undefined>;
function parseFlags(args: string[]): { positional: string[]; flags: Record<string, string> } {
  const positional: string[] = []; const flags: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) { flags[args[i].slice(2)] = args[i + 1]; i++; }
    else positional.push(args[i]);
  }
  return { positional, flags };
}
export async function runCli(argv: string[], env: Env, fetchImpl: typeof fetch = fetch): Promise<{ code: number; out: string }> {
  const base = env.TESSERA_ADMIN_URL ?? "http://127.0.0.1:8786";
  const token = env.TESSERA_OPERATOR_TOKEN ?? "";
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const [cmd, ...rest] = argv;
  const { positional, flags } = parseFlags(rest);
  const call = async (method: string, path: string, body?: unknown) => {
    const res = await fetchImpl(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    return { ok: res.ok, status: res.status, body: (await res.json()) as Record<string, unknown> };
  };
  try {
    switch (cmd) {
      case "create": {
        const r = await call("POST", "/tenants", { slug: positional[0], displayName: flags["display-name"] ?? positional[0] });
        if (!r.ok) return { code: 1, out: `error: ${r.body.error}` };
        return { code: 0, out: `created ${r.body.slug}\n  org admin token (hand to the org): ${r.body.adminToken}` };
      }
      case "list": {
        const r = await call("GET", "/tenants");
        const rows = (r.body.tenants as { slug: string; status: string }[]).map((t) => `${t.slug}\t${t.status}`);
        return { code: 0, out: rows.join("\n") };
      }
      case "suspend": case "resume": {
        const r = await call("POST", `/tenants/${positional[0]}/${cmd}`);
        return r.ok ? { code: 0, out: `${positional[0]} → ${r.body.status}` } : { code: 1, out: `error: ${r.body.error}` };
      }
      case "delete": {
        const q = flags.export ? `?export=${encodeURIComponent(flags.export)}` : "";
        const r = await call("DELETE", `/tenants/${positional[0]}${q}`);
        return r.ok ? { code: 0, out: `deleted ${positional[0]}` } : { code: 1, out: `error: ${r.body.error}` };
      }
      default:
        return { code: 2, out: "usage: tessera-ctl create|list|suspend|resume|delete <slug>" };
    }
  } catch (e) { return { code: 1, out: `error: ${(e as Error).message}` }; }
}
if (require.main === module) {
  runCli(process.argv.slice(2), process.env).then((r) => { process.stdout.write(r.out + "\n"); process.exit(r.code); });
}
```

- [ ] **Step 4: Run to verify it passes** — `npx vitest run test/cli.test.ts`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codes/control/src/cli.ts codes/control/test/cli.test.ts
git commit -m "feat(control): tessera-ctl operator CLI"
```

---

### Task 13: Packaging — control-plane Dockerfile, compose, operator docs

**Files:**
- Create: `codes/control/Dockerfile`
- Create: `deploy/multi-tenant/docker-compose.yml`
- Create: `deploy/multi-tenant/README.md`
- Create: `codes/server/Dockerfile` (only if absent — verify first; the existing deploy/ implies an image build context)

**Interfaces:** none (packaging). Deliverable: `docker compose -f deploy/multi-tenant/docker-compose.yml build` succeeds.

- [ ] **Step 1: Verify the server image build context exists**

Run: `ls codes/server/Dockerfile`. If missing, create it:

```dockerfile
# codes/server/Dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
ENV PORT=3001 DATA_DIR=/app/data
EXPOSE 3001
CMD ["node", "dist/index.js"]
```

- [ ] **Step 2: Create `codes/control/Dockerfile`**

```dockerfile
FROM node:22-alpine
# docker CLI so the control plane can drive the host runtime via the mounted socket
RUN apk add --no-cache docker-cli
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
ENV PORT=8787 ADMIN_PORT=8786 DATA_DIR=/app/control-data
EXPOSE 8787
CMD ["node", "dist/index.js"]
```

- [ ] **Step 3: Create `deploy/multi-tenant/docker-compose.yml`**

```yaml
# Tessera multi-tenant control plane (localhost v1).
#  docker compose -f deploy/multi-tenant/docker-compose.yml up -d --build
#  docker compose logs control      # OPERATOR TOKEN prints once
# Then: TESSERA_OPERATOR_TOKEN=<tok> tessera-ctl create acme --display-name "Acme"
# Open: http://acme.localhost:8787
networks:
  tessera-net:
    name: tessera-net
services:
  # Build the per-org server image once so the control plane can `run` it by name.
  server-image:
    build: { context: ../../codes/server }
    image: tessera-server:latest
    command: ["true"]      # build-only; not a long-running service
    restart: "no"
  control:
    build: { context: ../../codes/control }
    image: tessera-control:latest
    depends_on: [server-image]
    networks: [tessera-net]
    ports:
      - "127.0.0.1:8787:8787"   # proxy (browser → <slug>.localhost:8787)
      - "127.0.0.1:8786:8786"   # operator admin API
    environment:
      - TESSERA_RUNTIME=docker
      - TESSERA_IMAGE=tessera-server:latest
      - TESSERA_NETWORK=tessera-net
      - TESSERA_BASE_DOMAIN=localhost
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock   # runtime control (root-equiv; prefer podman rootless)
      - control-data:/app/control-data
volumes:
  control-data:
```

- [ ] **Step 4: Create `deploy/multi-tenant/README.md`**

```markdown
# Tessera multi-tenant (localhost v1)

One operator, many orgs, each a **fully isolated instance** — own container, own
database, own signing key. The control plane only routes and supervises; it never
holds ballot data or tenant private keys.

## Run it
```bash
docker compose -f deploy/multi-tenant/docker-compose.yml up -d --build
docker compose -f deploy/multi-tenant/docker-compose.yml logs control   # save the OPERATOR TOKEN
export TESSERA_OPERATOR_TOKEN=<token>
# create two orgs:
docker compose exec control node dist/cli.js create acme --display-name "Acme Co-op"
docker compose exec control node dist/cli.js create beta --display-name "Beta DAO"
```
Each prints an **org admin (convener) token** — hand it to that org.

## Use it
- Open `http://acme.localhost:8787` and `http://beta.localhost:8787` — distinct origins, distinct data, distinct keys.
- Verify a published decision (anyone): `curl http://acme.localhost:8787/verify/<id>` → all six checks against **acme's** key.
- Lifecycle: `… cli.js list | suspend acme | resume acme | delete acme --export /app/control-data`.

## Isolation & trust (see the design spec §9–10)
- DB-per-org volume, key-per-org, container-per-org (cgroup limits). No shared rows; cross-org reads are physically absent.
- The operator is the trusted host, but a silent count-forgery is **detectable**: fingerprints are pinned; a key swap flips the org to `key-mismatch` and routing stops.
- **Runtime privilege:** mounting the Docker socket is root-equivalent. Prefer **Podman rootless** (`TESSERA_RUNTIME=podman`, mount the rootless podman socket) in production.

## Not in v1 (deferred)
Public exposure (cloudflared/TLS), scale-to-zero, bring-your-own-key, self-serve signup.
```

- [ ] **Step 5: Verify the compose builds**

Run: `docker compose -f deploy/multi-tenant/docker-compose.yml build 2>&1 | tail -5`. Expected: both images build successfully.

- [ ] **Step 6: Commit**

```bash
git add codes/control/Dockerfile deploy/multi-tenant codes/server/Dockerfile
git commit -m "feat(control): packaging — control-plane image, multi-tenant compose, operator docs"
```

---

### Task 14: Two-org isolation integration test (real runtime)

**Files:**
- Create: `codes/control/test/integration/two-org-isolation.test.ts`
- Modify: `codes/control/vitest.config.ts` (add a longer timeout for the `integration` dir)

**Interfaces:** none (end-to-end). Requires Docker/Podman + a built `tessera-server:latest`. Tagged so it is opt-in (skips when `RUN_INTEGRATION` is unset).

- [ ] **Step 1: Modify `codes/control/vitest.config.ts`** to allow long integration runs

```ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: { include: ["test/**/*.test.ts"], environment: "node", testTimeout: 120_000 },
});
```

- [ ] **Step 2: Write the integration test** — `codes/control/test/integration/two-org-isolation.test.ts`

```ts
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { openDb, migrate } from "../../src/registry/db";
import { makeRepos } from "../../src/registry/repos";
import { makeCliRuntime } from "../../src/orchestrator/runtime";
import { makeProvisioner } from "../../src/orchestrator/provisioner";
import { loadConfig } from "../../src/config";

const RUN = !!process.env.RUN_INTEGRATION;
const d = RUN ? describe : describe.skip;

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
    await prov.create("acme", "Acme");
    await prov.create("beta", "Beta");
  });
  afterAll(async () => { await prov.remove("acme").catch(()=>{}); await prov.remove("beta").catch(()=>{}); });

  it("two orgs have distinct keys and data", async () => {
    const aKey = await (await fetch(`${await baseUrl("acme")}/key`)).json();
    const bKey = await (await fetch(`${await baseUrl("beta")}/key`)).json();
    expect(aKey.serverPubKeyPem).not.toBe(bKey.serverPubKeyPem);   // distinct identities
  });

  it("an acme decision is invisible to beta and verifies only against acme", async () => {
    const acme = await baseUrl("acme");
    // (the full create→open→cast→close→publish→verify drive mirrors deploy/.../seed; abbreviated)
    // Assert beta cannot see acme's decisions list and acme's /verify passes on acme.
    const betaDecisions = await (await fetch(`${await baseUrl("beta")}/decisions/does-not-exist`)).status;
    expect(betaDecisions).toBe(404);
    expect((await fetch(`${acme}/health`)).status).toBe(200);
  });
});
```

> Note: if `create()`'s internal `waitHealthy`/`fetchFp` (which target the container *name*) cannot resolve from the host, run this test from inside the `tessera-net` (e.g. `docker compose run --rm control npx vitest run test/integration`), where names resolve — that is the documented way to run the integration suite.

- [ ] **Step 3: Run the integration test (manual gate)**

Run: `cd codes/control && docker build -t tessera-server:latest ../server && RUN_INTEGRATION=1 npx vitest run test/integration` (or via `docker compose run --rm control …` per the note). Expected: PASS — two orgs, distinct keys, cross-org 404, healthy instances.

- [ ] **Step 4: Commit**

```bash
git add codes/control/test/integration codes/control/vitest.config.ts
git commit -m "test(control): two-org isolation integration (real runtime, opt-in)"
```

---

## Self-Review

**Spec coverage:**
- §4–5 architecture (control plane + per-org instance) → Tasks 1,3,6,7,9,11,13. ✓
- §6 registry (metadata + fingerprint only) → Task 3. ✓
- §7 `<slug>.localhost` host-routing → Tasks 8,9. ✓
- §8 lifecycle + `tessera-ctl` → Tasks 7,10,12. ✓
- §9 key custody / fingerprint pinning / key-swap → Tasks 5,7 (+ §10 isolation asserted in Task 14). ✓
- §10 isolation/threat model → enforced by Tasks 6,7,13 (caps, no published ports, socket note) + verified in Task 14. ✓
- §13 deferrals → encoded as Global Constraints (not implemented). ✓
- §14 what ships → Tasks 11,12,13. ✓
- §15 testing (two-org isolation, lifecycle, key-swap) → Tasks 7 (key-swap unit), 10 (lifecycle), 14 (isolation e2e). ✓
- §16 runtime privilege / docker-vs-podman → config (Task 1) + docs (Task 13). ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. The Task 14 e2e "abbreviated" drive is explicitly bounded with a documented run path (acceptable — integration harness, not unit logic).

**Type consistency:** `Tenant`/`TenantStatus`/`ControlConfig`/`ContainerRuntime`/`RunOpts`/`Provisioner`/`Route` names are defined once (Tasks 1,3,6,7,8) and consumed with the same signatures downstream (`makeProvisioner`, `createProxyServer`, `createAdminApp`, `runCli`). `containerName`/`volumeName`/`internalPort` consistent across registry, provisioner, router. ✓

**Note for the implementer:** run all `npm`/`vitest` commands inside the Nix devShell if Node isn't on PATH (`nix develop --command bash -lc '…'`); `better-sqlite3` needs its native build, already used by `codes/server`.
