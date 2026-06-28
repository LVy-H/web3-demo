# Releasing

> Updated for the **2026-06-19 self-hosted redesign**. The old testnet/mainnet contract
> flows are gone — **there are no smart contracts since the redesign**. A release is now a
> **git tag + GitHub release**, and "deploy" means **self-host** (local demo or the `deploy/`
> docker-compose path). See [VERSIONING.md](./VERSIONING.md).

## What a release is

A **git tag `vX.Y.Z`** on `main` plus a **GitHub release** carrying the matching CHANGELOG
excerpt. There is nothing to deploy to a public network — anyone who wants to run Tessera
**self-hosts** it. The release is the thing operators pull and run.

| Surface | What ships | How it runs |
|---------|-----------|-------------|
| **Client** (`codes/app`) | Flutter web/desktop/Android build | `./demo.sh up` (local) or any static host for the web build |
| **Server** (`codes/server`) | the self-hosted ballot-log + verifier service | Docker / docker-compose, or `dev-stack.sh up` for local dev |
| **Control plane** (`codes/control`) | multi-tenant operator proxy + `tessera-ctl` | `deploy/` docker-compose |

## Release checklist

### Pre-release
- [ ] CI green on `main` — the **`app`**, **`android`**, and **`server`** jobs all pass.
- [ ] **Client**: `dart run melos run analyze` clean; `dart run melos run test` green;
      `flutter build web` succeeds.
- [ ] **Server**: `npm test` green; `npm run build` succeeds; the running-server smoke passes.
- [ ] **Control plane**: `npm test` green; `npm run build` succeeds.
- [ ] **Critic-audited**: each merged PR was reviewed by an adversarial critic agent + GitHub
      Copilot, findings addressed.
- [ ] **Verified-or-fenced**: every shipped path is runtime-verified, or fenced so unverified
      code is inert and can't regress a working path.
- [ ] No uncommitted changes on the release branch.
- [ ] `CHANGELOG.md` has an `## [Unreleased]` section with the actual changes.
- [ ] Claims are honest (design §13) — in particular the single-party-trust caveat is intact.

### Cut the release
1. Decide the version number per [VERSIONING.md](./VERSIONING.md).
2. Update `CHANGELOG.md`: rename `## [Unreleased]` → `## [vX.Y.Z] — YYYY-MM-DD`, add a fresh
   empty `## [Unreleased]` above it.
3. **Bump all three aligned version files** so they stay in sync:
   - `codes/app/apps/tessera/pubspec.yaml` → `version: X.Y.Z+N`
   - `codes/server/package.json` → `"version": "X.Y.Z"`
   - `codes/control/package.json` → `"version": "X.Y.Z"`
4. Update `STATUS.md` (snapshot date + where-things-stand), move the active marker in
   `ROADMAP.md`, and clear `FOCUS.md` to the next iteration's goal.
5. Commit: `chore: release vX.Y.Z — <headline>`.
6. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
7. Push the commit and the tag; create the **GitHub release** from the tag with the CHANGELOG
   excerpt as the body.

## Deploy = self-host

There is no testnet or mainnet. To run a release:

### Local (one command)
```bash
./demo.sh up      # server + Flutter web client, locally
```
For server-only local dev (the client run separately via `flutter run`):
```bash
./dev-stack.sh up # starts codes/server on :3001, waits for /health
```

### Production (docker-compose, self-hosted)
```bash
cd deploy/<target>            # docker-compose self-host path
docker compose up -d
```
The multi-tenant control plane (`deploy/multi-tenant/`) runs many isolated org instances
behind a host-routing proxy; `tessera-ctl` is the operator CLI. Operator ops (TLS, backing up
the `data/` volume **including the credential keys**, the optional funded-wallet anchor path)
are hardened in Phase 6 — see [ROADMAP.md](./ROADMAP.md).

## Rollback

Self-hosted, so rollback is the operator's: redeploy the previous tag's image, restore the
`data/` volume from backup if a migration went wrong. Because published ballots, receipts, the
anchored Merkle root, and the credential protocol are stable wire formats (a MAJOR-bump
contract — see VERSIONING.md), an older verifier still checks a decision published by a newer
server within the same major.

## Communication

- **Internal:** `STATUS.md` update + a message in your shared channel.
- **External:** the tagged GitHub release with the CHANGELOG excerpt; operators pull the new
  tag and redeploy.
