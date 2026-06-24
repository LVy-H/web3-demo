# Tessera multi-tenant — isolated-instance-per-org (localhost-first v1)

**Status:** Design approved 2026-06-24. Ready for implementation planning.
**Scope of this spec:** v1, localhost-only. Public exposure, TLS, and scale features are explicit non-goals (see §13).

## 1. Goal

Let **one operator run many organizations** on a single deployment, where each org gets a
**genuinely private workspace** — not a `tenant_id` column on shared rows, but an
**OS-level boundary**: its own process/container, its own database, and its own
cryptographic identity. "Tenant" here means *a whole independent Tessera instance*, so
isolation is a property of the substrate, not of remembering a `WHERE` clause.

The bar (stated by the operator): **isolation an engineer would call real, not marketing.**

## 2. Scope

### In scope (v1)
- A **control plane** (`tessera-control`) that provisions, routes to, and supervises one
  isolated **per-org instance** of the existing server.
- **Container-per-org** isolation via Docker/Podman (own volume = own DB + own signing key).
- **Host-based routing** on localhost: `http://<slug>.localhost:8787` → that org's instance.
- A tenant **registry** holding routing metadata + the org's public-key **fingerprint** only.
- An operator CLI (`tessera-ctl`): `create | list | suspend | resume | delete | verify`.
- **Per-org verification** working through the proxy (free — each instance serves its own
  `/key` and `/verify`).
- **Key-swap detection** via first-seen fingerprint pinning.

### Non-goals (deferred — see §13)
- Public exposure via cloudflared / `*.lvh.id.vn`, and edge TLS. (Phase 2.)
- Scale-to-zero / hibernation of idle instances.
- Bring-your-own-key provisioning.
- Self-serve org signup, billing, a cross-org operator web UI.

The v1 deliverable is a **complete, demonstrable, properly-isolated multi-tenant system on
localhost** — just not yet publicly exposed. The routing model is chosen so public exposure
is a later drop-in (§7).

## 3. Background — what we're replacing

Today a server instance is `loadOrCreateServerKey(DATA_DIR)` → **one** `serverKey` shared by
every router, **one** SQLite DB, **one** public namespace. `bootstrapAdmin` mints one admin;
`accounts` (conveners) and `decisions` (scoped by `convener_id`) all live together. Running
several orgs on one server today means **they share one signing key and can see each other's
decisions.** That shared key + shared namespace is exactly what a private workspace must break.

The existing single-tenant server (`codes/server`) is **not modified** by this design. It
already does everything an org needs; multi-tenancy is added *around* it.

## 4. Architecture

```
                http://<slug>.localhost:8787   (browser maps *.localhost → 127.0.0.1)
                          │
                  ┌───────▼──────────┐
                  │  tessera-control │  container, publishes 127.0.0.1:8787 only
                  │  ┌────────────┐  │  • host-routing reverse proxy (by Host header)
                  │  │ registry DB│  │  • orchestrator (Docker/Podman API)
                  │  └────────────┘  │  • operator admin API  ← tessera-ctl
                  └───┬────┬────┬────┘  holds: routing metadata + key FINGERPRINTS
                      │    │    │        never: ballot data · never: tenant private keys
   private bridge net │    │    │  (containers unpublished; reachable only by name)
   ┌──────────────────▼┐ ┌─▼──────────┐ ┌▼───────────────┐
   │ tessera-acme:3001 │ │tessera-beta│ │ tessera-gamma  │   ← the EXISTING server image,
   │ vol tessera-acme  │ │vol …-beta  │ │ vol …-gamma    │     one container per org, UNCHANGED
   │ key (in volume)   │ │key …       │ │ key …          │     own DB + own Ed25519 key
   └───────────────────┘ └────────────┘ └────────────────┘
```

- **Data plane** = N× the existing `tessera-server`, one container per org, each with a named
  volume mounted at `DATA_DIR` (holding `tessera.db` + the org's signing key). Containers are
  **not** published to the host; they sit on a private user-defined bridge network and are
  reachable only as `tessera-<slug>:3001`.
- **Control plane** = one new service (Node/TS, same stack: express + better-sqlite3),
  itself a container on that same network, publishing **only** `127.0.0.1:8787`. It is the
  sole ingress.

## 5. Components

### 5.1 Per-org instance (data plane) — unchanged
The current server image (`tessera-server:latest`, built from `codes/server`). On first boot
in a fresh volume it mints its signing key and prints its admin (convener) token once. It
serves its own `/health`, `/key`, `/verify/:id`, and all decision routes. **No code changes.**

### 5.2 Control plane (`tessera-control`) — new
Four responsibilities, each a focused module:

1. **Registry** (`registry/`) — a SQLite DB (control-plane-only) + repo. Schema in §6. Holds
   no ballot data and no private keys.
2. **Orchestrator** (`orchestrator/`) — talks to the container runtime (Docker Engine API via
   the mounted socket; Podman's compatible socket also works). Creates/starts/stops/removes
   per-org containers and named volumes; applies per-container CPU/memory limits.
3. **Host-routing proxy** (`proxy/`) — an in-process HTTP reverse proxy. Parses the `Host`
   header (`<slug>.localhost`), looks up the tenant, and forwards to `http://tessera-<slug>:3001`.
   Unknown slug → 404; `suspended` → 503; `key-mismatch` → 503 + operator alert.
4. **Operator admin API** (`admin/`) — authenticated (operator-admin bearer token) routes
   backing the CLI: `POST /tenants`, `GET /tenants`, `POST /tenants/:slug/{suspend,resume}`,
   `DELETE /tenants/:slug`. Bound to the admin port, never proxied to tenants.

### 5.3 CLI (`tessera-ctl`)
Thin client over the admin API: `create <slug> [--display-name]`, `list`, `suspend <slug>`,
`resume <slug>`, `delete <slug> [--export <path>]`, `verify <slug> <decisionId>`.

## 6. Control-plane registry schema (metadata only)

```sql
CREATE TABLE tenants (
  slug            TEXT PRIMARY KEY,   -- DNS-safe [a-z0-9-]{1,40}; → <slug>.localhost
  display_name    TEXT NOT NULL,
  status          TEXT NOT NULL,      -- provisioning|active|suspended|deleting|key-mismatch
  container_name  TEXT NOT NULL,      -- tessera-<slug>
  volume_name     TEXT NOT NULL,      -- tessera-<slug> (data volume)
  internal_port   INTEGER NOT NULL,   -- 3001 (per-container, not host-published)
  key_fingerprint TEXT,               -- sha256 of /key SPKI, pinned on first active boot
  created_at      INTEGER NOT NULL
);
CREATE TABLE operator_admins (        -- who may call the control admin API
  id          TEXT PRIMARY KEY,
  token_hash  TEXT NOT NULL UNIQUE,   -- SHA-256, plaintext shown once on bootstrap
  created_at  INTEGER NOT NULL
);
```
Reserved slugs (blocked): `www`, `admin`, `api`, `control`, `health`, `localhost`.

## 7. Request routing / tenant resolution (localhost)

- Browser: `http://acme.localhost:8787` — `*.localhost` resolves to loopback natively (RFC
  6761; browsers + systemd-resolved honor it), so **no DNS/TLS/hosts config**. Each org also
  gets a **distinct browser origin** → cookie/CORS isolation holds even locally.
- CLI/non-browser: `curl -H 'Host: acme.localhost' 127.0.0.1:8787/verify/<id>`.
- The proxy forwards to `http://tessera-acme:3001` over the private bridge network.

**Forward-compatibility (the reason localhost-first costs nothing):** Phase 2 puts cloudflared
in front of the *same* proxy — `*.lvh.id.vn` → tunnel → `127.0.0.1:8787` → identical Host
routing. No routing code changes when going public; only an ingress/TLS layer is added.

## 8. Provisioning & lifecycle

State machine: `provisioning → active ⇄ suspended → deleting → (removed)`; plus
`active → key-mismatch` on a detected key swap.

**create `<slug>`:**
1. Validate slug (regex + reserved list); reject if exists.
2. Create named volume `tessera-<slug>`.
3. `docker run -d --name tessera-<slug> --network tessera-net --restart unless-stopped
   --memory=${TESSERA_TENANT_MEM:-256m} --cpus=${TESSERA_TENANT_CPUS:-0.5}
   -v tessera-<slug>:/app/data -e PORT=3001 -e DATA_DIR=/app/data
   tessera-server:latest` (no published ports; resource caps are configurable defaults).
4. Poll `http://tessera-<slug>:3001/health` until ok (timeout → rollback: remove container,
   keep or drop volume, status stays `provisioning`/error).
5. `GET /key` → compute fingerprint → store as `key_fingerprint` (pin).
6. Read the admin token from the container's first-boot log; return it to the operator **once**
   to hand to the org. Control plane does **not** persist it.
7. `status = active`.

**suspend:** stop container, keep volume; proxy → 503. **resume:** start container; on start,
re-read `/key` and compare to the pinned fingerprint (see §9). **delete:** optional
`--export` (tar the volume = the org's ballot record) → stop + remove container + remove volume
→ remove registry row.

## 9. Key custody & verifiability (the trust boundary)

- Each org's Ed25519 signing key is **generated inside its instance** on first boot and lives
  **only in that org's volume**. The control plane sees only the **public fingerprint**.
- Anyone — org member or public — verifies a published decision by fetching the bundle + `/key`
  via `<slug>.localhost:8787` and running the independent verifier (`npm run verify`). The count
  binds to *that org's* key.
- **Operator-cheating is detectable, not invisible.** The only way the operator could forge a
  count is to swap an org's key/volume. Defenses:
  - **Fingerprint pinning:** the registry pins the first-seen fingerprint; on every
    start/resume the control plane re-reads `/key` and, on mismatch, sets `key-mismatch`,
    **refuses to route**, and alerts the operator.
  - **Out-of-band publication:** orgs publish their fingerprint (their own channel) so members
    detect a swap independently of the operator.
  - (Phase 2: bring-your-own-key, so the operator never holds the key at all.)
- **Privacy bonus:** the secret-ballot blind-signature design means even the hosting operator
  **cannot link a vote to a voter** — anonymity survives the trusted host. (Open-ballot data is
  inherently visible to whoever runs the instance; this is unchanged and disclosed.)

## 10. Isolation guarantees & threat model

| Axis | Mechanism | What a bug/attacker confined to org A **cannot** do |
|---|---|---|
| Data | separate DB file in a separate volume | reach org B's data — no shared handle exists |
| Identity | separate Ed25519 key per org | forge org B's anchor / impersonate B |
| Process/memory | separate container + cgroups | read B's memory; starve B (CPU/mem caps) |
| Network | instances unpublished; proxy is sole ingress | address B's instance directly |
| Blast radius | per-container supervision | take down or compromise anything but A |

**Trusted:** the operator (to run honestly + keep the host secure) — exactly today's
self-host, at scale. **Not required to be trusted for integrity:** verifiability + fingerprint
pinning make a silent count-forgery detectable. **Known accepted v1 exposure:** the control
plane terminates plaintext between proxy and instance on the operator's own box (integrity
unaffected; secret-ballot anonymity preserved by blind-sig). **Privilege note:** the control
plane needs the container-runtime socket (root-equivalent for Docker) — mitigate with **Podman
rootless**; documented as an operator risk.

## 11. Client impact

Minimal. The Flutter app already supports a configurable server URL ("one build, many
backends"). An org's URL **is** the tenant (`http://acme.localhost:8787`), shared as a
link/QR. No app-side tenant logic; no per-tenant build.

## 12. Migration / backward compatibility

- Single-tenant self-host is **unchanged** — just `tessera-server`, no control plane.
- An existing single instance can be **adopted** as a tenant (register its slug → its existing
  volume; pin its current fingerprint). Supported, not a v1 focus.
- Multi-tenant ships as a **first-class, opt-in** component ("native"), not a replacement.

## 13. Deferred (Phase 2+)

| Item | Why deferred |
|---|---|
| cloudflared `*.lvh.id.vn` + edge TLS | public exposure; routing is already forward-compatible (§7) |
| scale-to-zero / hibernation | needed only at many-idle-orgs scale; v1 is always-on |
| bring-your-own-key | strongest anti-cheat story but adds provisioning UX |
| self-serve signup, billing, operator web UI | operator-provisioned (CLI) is enough for v1 |

## 14. What ships (v1)

- `tessera-control` service (registry · orchestrator · host-routing proxy · admin API).
- `tessera-ctl` CLI.
- `deploy/multi-tenant/` compose: control plane + the private bridge network + the per-org
  `tessera-server` image. (No cloudflared yet.)
- Docs: operator quickstart (run control plane → `tessera-ctl create acme` → open
  `acme.localhost:8787` → hand the org its admin token), isolation/threat-model notes.
- Per-org image = the existing server, untouched.

## 15. Testing strategy & acceptance criteria

**Unit:** slug validation + reserved list; registry repo; fingerprint computation + pinning;
proxy Host→tenant resolution (unknown/suspended/key-mismatch branches) with a mocked runtime.

**Integration (real Docker/Podman, two orgs `acme` + `beta`):**
- Provision both; assert two containers, two volumes, two **distinct** `/key`s.
- **Cross-tenant isolation:** a decision created in `acme` is absent from `beta`'s API; an
  `acme` decision's published result **fails** verification against `beta`'s key and **passes**
  against `acme`'s.
- **Lifecycle:** suspend → 503; resume → 200; delete → row + container + volume gone;
  `--export` produces a restorable tar.
- **Key-swap detection:** replace a tenant's volume/key out-of-band → on resume, status
  becomes `key-mismatch` and routing is refused.

**E2E:** via `tessera-ctl`, create `acme` + `beta`, seed a decision in each through the proxy
(`<slug>.localhost`), independently verify each (all §11 checks pass), confirm distinct origins.

**Acceptance:** two orgs run fully isolated on localhost (data + key + process), each
independently verifiable, full lifecycle works, key-swap is detected — using the **unmodified**
server image.

## 16. Risks & open questions

- **Container-runtime socket privilege** (Docker = root-equiv). Mitigation: document + prefer
  Podman rootless. Confirm target runtime with operator before implementation.
- **Always-on container footprint** at higher org counts — accepted for v1; scale-to-zero is
  the planned relief (§13).
- **Image distribution** — the control plane assumes `tessera-server:latest` is built/available
  locally; the compose builds it from `codes/server`.
- **`*.localhost` resolution on the operator's box** — true for browsers + systemd-resolved;
  the `Host`-header CLI form is the fallback if a resolver is non-conformant.
