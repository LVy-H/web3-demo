# Status

> **Snapshot:** 2026-06-02 — keep this date current when editing.

## TL;DR

A working PoC of a modular ZK voting system runs end-to-end on a local Hardhat node. **Two voting modules shipped** (M1 anon-vote, M2 blind-vote), plus a standalone `ZkAirdrop`. **No deployment beyond local Hardhat.** Several known bugs (see `improvements/findings.md` P0).

> **Canonical client (2026-06-02): the Flutter app `codes/mobile/` — "Tessera" —
> across mobile, desktop, AND web.** It has reached parity with the old React app
> (browse / create / M1 / M2 blind-vote / verify-receipts / identity / live-meeting
> host + voter) and adds desktop ZK proving (Node sidecar) + a dev-signer.
> The **React 19 + Wagmi + Viem app at `codes/frontend/` is DEPRECATED** (legacy);
> see `codes/frontend/DEPRECATED.md` for the two dev-toolchain couplings to
> decouple before it can be removed.

## Shipped (works today)

### Contracts (`codes/contracts/`)
- `PollRegistry` — EIP-1167 factory, two modules registered (`anon-vote`, `blind-vote`)
- `ZkAnonVoting` (M1) — Semaphore-based anonymous voting; tested ✓
- `ZkBlindVoting` (M2) — commit-reveal voting; tested ✓
- `ZkAirdrop` — standalone Semaphore-gated ETH airdrop; **untested** ✗
- `MockSemaphoreVerifier` — local verifier that always returns true (no SNARK artifacts needed)
- Deploy script wires it all together and writes `deployed-addresses.json` for the frontend

### Frontend (`codes/frontend/`)
- Pages: Home (poll list), CreatePoll (with module-type selector), Poll (M1), BlindPoll (M2), PollRouter (dispatches by module type)
- Hooks: `useRegistry`, `usePoll` (IZkPoll-generic), `useBlindPoll` (M2-specific)
- Wallet integration: MetaMask via Wagmi, auto-add Hardhat network on connect
- UI: dark/light mode, teal-accent visual system per `standards/visual-design-guide.md`
- E2E: Playwright spec covers the M1 happy path

### Infra
- `docker-compose.yml` for the full stack (Hardhat node + frontend), stale and probably broken — see [improvements P0-4](../improvements/findings.md)
- Nix flake for reproducible local toolchain

## In flight

> Track the current iteration's work in [FOCUS.md](./FOCUS.md). Items here are mid-implementation but not blocked.

*(empty — fill in when work starts)*

## Blocked / known broken

Severity from `improvements/findings.md`:

- **[P0-1]** `localStorage['my-nullifier']` is global, not per-poll → user appears voted across polls.
- **[P0-2]** Module-scope `let group` / `let isGroupSynced` in `Poll.tsx` leak across navigation.
- **[P0-3]** `ZkAirdrop` has zero tests.
- **[P0-4]** Top-level docs (`codes/README.md`, `codes/INSTRUCTIONS.md`, `codes/ZkVotingAirdrop_System_Workflow.md`) describe the old `ZkVotingLottery` design and mislead readers.

These don't block local dev but block any external use.

## Not started

- Real Groth16 verifier path in tests (only `MockSemaphoreVerifier` exercised)
- CI (no `.github/workflows/`)
- Testnet deployment of any kind
- Pagination / event-driven poll list (current `getAllPolls` polls every 5s — won't scale past dozens of polls)
- M3 (Participation Receipts as a cross-cutting feature) — `verifyParticipation()` exists in IZkPoll but no UI surface
- Phase 5 integration layer (SDK / API for third-party use)

## Health metrics

| Metric | Value | Target | Source |
|---|---|---|---|
| Contracts test count | 17 across 3 files | n/a | `codes/contracts/test/` |
| Frontend lint | passes | passes | `npm run lint` in `codes/frontend/` |
| `npm run deploy:local` reproducible | yes | yes | deterministic Hardhat addresses |
| CI status | none | green on every PR | — |
| Open P0 items | 4 | 0 | `improvements/findings.md` |
| Open P1 items | 8 | 0 before any deploy | `improvements/findings.md` |

## How to update this file

- Move items between sections as work progresses.
- Add a dated entry at the top of "In flight" when work starts (`YYYY-MM-DD - what + who`).
- When something ships, **delete the in-flight entry** and update "Shipped". Don't accumulate a history here — that's CHANGELOG's job.
