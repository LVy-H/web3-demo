# Improvements Log

A shared, durable record of everything we want to fix in this repo. Two-person workflow: pick an unowned item, set yourself as `Owner`, flip status, open a PR referencing the item ID.

## Files

- **[architecture-context.md](./architecture-context.md)** — non-obvious things you must know before touching the code. Read first.
- **[findings.md](./findings.md)** — every concrete improvement, fully spec'd. Checklist + details.
- **README.md** *(this file)* — at-a-glance status board.

## How to use

1. Read `architecture-context.md` end-to-end on first contact. It's short.
2. Open `findings.md`, find an unclaimed `Status: Open` item that matches your priority band.
3. Edit the `Owner:` field to your name and flip `Status:` to `In Progress` in the same commit you create the branch.
4. Branch name convention: `imp/<item-id>-short-slug` (e.g. `imp/P0-1-per-poll-nullifier-key`).
5. PR title: `[<item-id>] <one-line summary>`. PR body links back to the item and shows the acceptance check passing.
6. After merge, flip `Status:` to `Done` in `findings.md` on `main`.

If you discover a new issue while working an item, **add a new entry to `findings.md`** instead of expanding the current one. One issue = one item = one PR. Keeps blast radius small.

## Priority bands (legend)

| Band | Meaning | Target |
|------|---------|--------|
| **P0** | Real bugs, missing tests on existing contracts, stale docs that mislead readers. | Fix this week. |
| **P1** | Contract security hardening: OZ Initializable/Ownable, pragma unify, escape hatches. | Fix before any external use. |
| **P2** | ~~Frontend refactor — break up the 855-LOC and 710-LOC React pages.~~ **Retired (MOOT)** — the React frontend was deleted; the Flutter client supersedes it. | — |
| **P3** | DX & CI — lint, format, GH Actions, remove committed cruft. | Background work. |
| **P4** | Production-readiness path — pagination, event indexing, real Groth16 in CI, SNARK artifact bundling. | After everything else. |

## Status board

Source of truth lives in `findings.md` — this table is a snapshot. If they disagree, `findings.md` wins.

### P0 — Bugs (4)

| ID | Title | Owner | Status | Branch |
|----|-------|-------|--------|--------|
| P0-1 | `localStorage['my-nullifier']` is global, not per-poll | — | Won't Fix (MOOT — React deleted) | — |
| P0-2 | Module-scope `let group` / `let isGroupSynced` in `Poll.tsx` | — | Won't Fix (MOOT — React deleted) | — |
| P0-3 | `ZkAirdrop` has no test file | — | Done | `imp/P0-3-airdrop-tests` |
| P0-4 | Top-level docs describe the old `ZkVotingLottery` design | — | Done | `imp/P0-4-readme-cleanup` |

### P1 — Contract security (9)

> **All DONE** — the contract-hardening pass is on `main` (verified 2026-06-03 against the contracts). P1-13 (cap value) closed by lowering the `registerVoters` cap to 50.

| ID | Title | Owner | Status | Branch |
|----|-------|-------|--------|--------|
| P1-5  | Replace hand-rolled `_initialized` with OZ `Initializable` | — | Done | — |
| P1-6  | Replace ad-hoc `onlyOwner` modifier with OZ `Ownable` / `Ownable2Step` | — | Done | — |
| P1-7  | Custom errors instead of revert strings | — | Done | — |
| P1-8  | Add `ReentrancyGuard` to `ZkAirdrop.claimAirdrop` | — | Done | — |
| P1-9  | Owner escape hatch for unclaimed airdrop ETH | — | Done | — |
| P1-10 | Unify Solidity pragma across all contracts | — | Done | — |
| P1-11 | `ZkAnonVoting.startVoting` should require ≥1 voter | — | Done | — |
| P1-12 | Cap batch size in `registerVoters` | — | Done | — |
| P1-13 | `registerVoters` cap of 100 exceeds mainnet block gas (→ lowered to 50) | — | Done | — |

### P2 — Frontend refactor (2)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P2-13 | Split `Poll.tsx` (855 LOC) into composed components + hooks | — | Won't Fix (MOOT — React deleted) |
| P2-14 | Split `BlindPoll.tsx` (710 LOC) into composed components + hooks | — | Won't Fix (MOOT — React deleted) |

### P3 — DX & CI (7)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P3-15 | Add `solhint` + `prettier-plugin-solidity` + `lint`/`format` scripts | — | Done |
| P3-16 | Add GitHub Actions CI (test + lint, all packages) | — | Done |
| P3-17 | Untrack `accounts.txt`, `hardhat-node.log` | — | Done |
| P3-18 | Remove committed binaries (`web3-demo.zip`, `system-description.pdf/.txt`) | — | Done |
| P3-19 | Loud banner when deploying with `MockSemaphoreVerifier` + a real-verifier deploy variant | — | Open |
| P3-20 | Parallel agents need git worktree isolation | — | Open |
| P3-21 | Dangling `codes/frontend/src/lib/*` provenance comments in the Flutter client | — | Open |

### P4 — Production readiness (5)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P4-20 | Document module immutability (clones can't be upgraded) | — | Open |
| P4-21 | Pagination for `getAllPolls` | — | Open |
| P4-22 | Event-driven poll list (replace `getAllPolls` polling) | — | Open |
| P4-23 | Real Groth16 verifier path in nightly CI | — | Open |
| P4-24 | SNARK artifact bundling instead of CDN fetch | — | Open |

## Discovery log

When you find a new issue mid-task, append a one-liner here with date + ID, then create the full entry in `findings.md`. Lets us track velocity without scrolling.

| Date | ID | Found by | Note |
|------|-----|----------|------|
| 2026-04-27 | P0-1..P4-24 | Initial codebase audit | Seed entries from first read-through |
| 2026-04-27 | P3-20 | Sprint 1 dispatch retrospective | Parallel agents sharing one working tree caused branch-checkout races; A2's commit briefly landed on A1's branch (recovered via `git rebase --onto`). Future sprints must use `isolation: "worktree"` per agent. |
| 2026-04-27 | P1-13 | A7 empirical gas measurement during P1-12 implementation | 100-element registerVoters costs ~50M gas — exceeds mainnet's 30M block limit and Hardhat's 16.7M tx cap. Cap value chosen in P1-12 was wrong; recommend lowering to 50 (mainnet-fits) or 25 (Hardhat-fits) or making it a configurable initializer arg. |
| 2026-06-03 | P3-21 | Docs-truth-up sweep | Repo-wide grep for stale React-frontend references surfaced ~12 dangling `codes/frontend/src/lib/*` provenance comments in the Flutter client (and a broken golden-vectors regenerate pointer). Deferred from the docs-only truth-up PR. |
| 2026-06-03 | P1-5..P1-12 | P1 premise re-check | All P1 hardening items were already implemented on `main` (OZ Initializable/Ownable, custom errors, airdrop ReentrancyGuard + escape hatch, unified pragma, anon invariants) but `findings.md` + the board still showed them Open. Verified against the contracts and flipped to Done; closed the lone real-open item P1-13 (cap → 50). |
