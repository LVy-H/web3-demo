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
- Lifecycle: `… cli.js list | suspend acme | resume acme | delete acme --export /tmp/acme-backup.tgz`. `--export` takes a path on the host (the Docker daemon's filesystem); the gzipped tar of the org's ballot log + key is written there.

## Isolation & trust (see the design spec §9–10)
- DB-per-org volume, key-per-org, container-per-org (cgroup limits). No shared rows; cross-org reads are physically absent.
- The operator is the trusted host, but a silent count-forgery is **detectable**: fingerprints are pinned; a key swap flips the org to `key-mismatch` and routing stops.
- **Runtime privilege:** mounting the Docker socket is root-equivalent. Prefer **Podman rootless** (`TESSERA_RUNTIME=podman`, mount the rootless podman socket) in production.

## Not in v1 (deferred)
Public exposure (cloudflared/TLS), scale-to-zero, bring-your-own-key, self-serve signup.
