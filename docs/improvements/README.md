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
| **P2** | Frontend refactor — break up the 855-LOC and 710-LOC pages. Pure refactor, no behavior change. | Do once, in one PR per page. |
| **P3** | DX & CI — lint, format, GH Actions, remove committed cruft. | Background work. |
| **P4** | Production-readiness path — pagination, event indexing, real Groth16 in CI, SNARK artifact bundling. | After everything else. |

## Status board

Source of truth lives in `findings.md` — this table is a snapshot. If they disagree, `findings.md` wins.

### P0 — Bugs (4)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P0-1 | `localStorage['my-nullifier']` is global, not per-poll | — | Open |
| P0-2 | Module-scope `let group` / `let isGroupSynced` in `Poll.tsx` | — | Open |
| P0-3 | `ZkAirdrop` has no test file | — | Open |
| P0-4 | Top-level docs describe the old `ZkVotingLottery` design | — | Open |

### P1 — Contract security (8)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P1-5  | Replace hand-rolled `_initialized` with OZ `Initializable` | — | Open |
| P1-6  | Replace ad-hoc `onlyOwner` modifier with OZ `Ownable` / `Ownable2Step` | — | Open |
| P1-7  | Custom errors instead of revert strings | — | Open |
| P1-8  | Add `ReentrancyGuard` to `ZkAirdrop.claimAirdrop` | — | Open |
| P1-9  | Owner escape hatch for unclaimed airdrop ETH | — | Open |
| P1-10 | Unify Solidity pragma across all contracts | — | Open |
| P1-11 | `ZkAnonVoting.startVoting` should require ≥1 voter | — | Open |
| P1-12 | Cap batch size in `registerVoters` | — | Open |

### P2 — Frontend refactor (2)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P2-13 | Split `Poll.tsx` (855 LOC) into composed components + hooks | — | Open |
| P2-14 | Split `BlindPoll.tsx` (710 LOC) into composed components + hooks | — | Open |

### P3 — DX & CI (5)

| ID | Title | Owner | Status |
|----|-------|-------|--------|
| P3-15 | Add `solhint` + `prettier-plugin-solidity` + `lint`/`format` scripts | — | Open |
| P3-16 | Add GitHub Actions CI (test + lint, both packages) | — | Open |
| P3-17 | Untrack `accounts.txt`, `hardhat-node.log` | — | Open |
| P3-18 | Remove committed binaries (`web3-demo.zip`, `system-description.pdf/.txt`) | — | Open |
| P3-19 | Loud banner when deploying with `MockSemaphoreVerifier` + a real-verifier deploy variant | — | Open |

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
