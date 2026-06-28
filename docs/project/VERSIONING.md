# Versioning

> Updated for the **2026-06-19 self-hosted redesign**. The old on-chain scheme (contract
> impl versions, per-network deployed-address ledgers, ABIs) is gone — see CHANGELOG `v0.4.0`.
> **There are no smart contracts since the 2026-06-19 redesign**; the product is a
> self-hostable server + a Flutter client, versioned together by repo semver.

This project ships three coordinated pieces that move together: the **Flutter client**
(`codes/app`), the **self-hosted server** (`codes/server`), and the **multi-tenant control
plane** (`codes/control`). One repo semver covers all three.

## TL;DR

- **Repo:** semver tags on the git repo for releases (`v0.4.0`).
- **Canonical version** lives in three files that are bumped together as part of the release
  commit and **kept aligned**:
  - `codes/app/apps/tessera/pubspec.yaml` — `version: X.Y.Z+N` (the client; `+N` is the
    build number, displayed on the Settings screen).
  - `codes/server/package.json` — `"version": "X.Y.Z"`.
  - `codes/control/package.json` — `"version": "X.Y.Z"`.
- **A release is a git tag `vX.Y.Z` + a GitHub release** carrying the CHANGELOG excerpt.
  See [RELEASING.md](./RELEASING.md).

## Repo versioning (semver)

| Bump | When |
|------|------|
| **MAJOR** (`1.x.x → 2.0.0`) | Breaking change to a public contract: the server REST API, the receipt / anchor / verifier wire formats, the credential protocol, or the on-disk `data/` schema in a way that isn't migrated. |
| **MINOR** (`0.4.x → 0.5.0`) | New feature — new voting method, new lifecycle capability, new server endpoint, control-plane feature — backward-compatible. |
| **PATCH** (`0.4.0 → 0.4.1`) | Bug fix, client-only change, doc update, refactor with no API/format change. |

**Pre-1.0 (where we are):** use `0.x.y` and treat any minor bump as potentially breaking.
We will iterate quickly and may break wire formats between minors until 1.0.

Move to **`1.0.0`** only when the roadmap's 1.0 bar is met — **Phases 5 and 6 done**:
product completeness (result semantics, notifications, lifecycle edits, abstain, share/export,
WCAG-AA voter path, i18n-ready) **and** 1.0 hardening (verification-protocol + credential
security review, durability/abuse hardening, one-command self-host packaging), with honest
claims (design §13) matching reality. See [ROADMAP.md](./ROADMAP.md).

## Keeping the three versions aligned

The client, server, and control plane share one repo semver. They are deployed together for a
given release, so a reader who sees `0.4.0` on the Settings screen knows which server + control
plane that build was cut against.

Bump all three in the same release commit. A pre-commit check or release script may diff the
three values and fail if they drift; today it is a manual checklist item in
[RELEASING.md](./RELEASING.md).

## What we don't do

- **No smart contracts, ABIs, or per-network deployed-address ledgers** — removed with the
  on-chain stack in Phase 1 (#133). There is nothing immutable-on-a-chain to version
  separately; the server's behaviour is the source of truth and moves with the repo.
- **No off-chain version negotiation.** The client targets the server REST API for its repo
  version; a breaking API change is a major (or, pre-1.0, a documented minor) bump, not a
  negotiated capability handshake.
- **Wire formats that *must* stay stable across versions** (published ballots, receipts, the
  anchored Merkle root, the credential protocol) so that an old verifier still checks an old
  decision — breaking any of these is a MAJOR bump and called out in CHANGELOG.
