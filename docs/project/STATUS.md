# Status

> **Snapshot:** 2026-06-03 — keep this date current when editing.

## TL;DR

A modular ZK voting system runs end-to-end on a local Hardhat node. **Six voting modules shipped full-stack** (M1 anon-vote, M2 blind-vote, approval-vote, ranked-vote, quadratic-vote, survey-vote), plus a standalone `ZkAirdrop`. **No deployment beyond local Hardhat.** All P0 items closed; 8 P1 contract-hardening items remain before any deploy (see `improvements/findings.md`).

> **Sole client (2026-06-02): the Flutter app `codes/mobile/` — "Tessera" —
> across mobile, desktop, AND web.** It reached parity with the old React app
> (browse / create / M1 / M2 blind-vote / verify-receipts / identity / live-meeting
> host + voter) and adds desktop ZK proving (Node sidecar) + a dev-signer.
> The **React 19 + Wagmi + Viem app (`codes/frontend/`) has been REMOVED** — the
> prover bundle is self-contained and the deployed-addresses fixture moved to
> `codes/contracts/`.

## Shipped (works today)

### Contracts (`codes/contracts/`)
- `PollRegistry` — EIP-1167 factory, six modules registered (`anon-vote`,
  `blind-vote`, `approval-vote`, `ranked-vote`, `quadratic-vote`, `survey-vote`)
- `ZkAnonVoting` (M1) — Semaphore-based anonymous voting; tested ✓
- `ZkBlindVoting` (M2) — commit-reveal voting; tested ✓
- `ZkApprovalVoting` / `ZkRankedVoting` / `ZkQuadraticVoting` (Phase 12a/12b/12c)
  — richer voting types; tested ✓
- `ZkSurveyVoting` (Phase 12d) — multi-question ("Google-Forms") survey: one
  ballot / one nullifier per survey, hash-commitment
  `message = keccak256(abi.encode(answers)) >> 8`, per-question single-choice /
  multi-select tallies. **Shipped full-stack** (contract + relayer + Flutter
  read/answer/cast/results + question-builder create flow); 45 hardhat tests ✓
- `ZkAirdrop` — standalone Semaphore-gated ETH airdrop; tested ✓ (`test/ZkAirdrop.test.ts`)
- `MockSemaphoreVerifier` — local verifier that always returns true (no SNARK artifacts needed)
- Deploy script wires it all together and writes `deployed-addresses.json` for the client
- **268 hardhat tests passing** across 9 test files

### Client — Tessera (`codes/mobile/`)
- One Flutter codebase across mobile, desktop, AND web. Browse / create
  (dev-signer or sponsored wallet-free) / per-module poll screens (M1, M2,
  approval, ranked, quadratic, survey) / verify-receipt / identity /
  live-meeting host + voter / settings.
- ZK proving: browser (web), Node sidecar (desktop), and headless
  `webview_flutter` (mobile, emulator-verified) — all against the real
  Groth16 vkey.
- Secure storage for the Semaphore seed, blind-vote salts, and org keypair.
- Static analysis clean (`flutter analyze`); test suite green (`flutter test`).

### Relayer (`codes/relayer/`)
- Optional Express service: gasless vote / airdrop-claim submission plus a
  sponsored (wallet-free) poll lifecycle. **96 vitest tests passing** (2 skipped).

### Infra
- `docker-compose.yml` — dev-only stack: `contracts` (Hardhat node) +
  `relayer` + `explorer`. The local-dev one-liner is `./dev-stack.sh up`.
- `.github/workflows/ci.yml` — three jobs (contracts / relayer / mobile).
- Nix flake for a reproducible local toolchain.

## In flight

> Track the current iteration's work in [FOCUS.md](./FOCUS.md). Items here are mid-implementation but not blocked.

*(empty — fill in when work starts)*

## Blocked / known broken

**All P0 items resolved (2026-06-02)** — see `improvements/findings.md`:

- ~~**[P0-1]** / **[P0-2]**~~ — React `Poll.tsx` bugs, **MOOT** (React frontend deleted; Flutter app supersedes).
- ~~**[P0-3]**~~ — **Done**: `ZkAirdrop.test.ts` exists; contracts suite 268 passing.
- ~~**[P0-4]**~~ — **Done**: stale `INSTRUCTIONS.md` / `ZkVotingAirdrop_System_Workflow.md` removed; README rewritten.

*(No open P0 items. Next release gate is Phase 10: Sepolia + real Groth16 verifier → `1.0`.)*

These don't block local dev but block any external use.

## Not started

- Real Groth16 verifier path in tests (only `MockSemaphoreVerifier` exercised; P4-23)
- Testnet deployment of any kind (Phase 10: Sepolia + real verifier → `1.0`)
- Pagination / event-driven poll list (current `getAllPolls` won't scale past dozens of polls; P4-21/P4-22)
- M3 (Participation Receipts as a cross-cutting feature) — `verifyParticipation()` exists in IZkPoll; surfaced in the client's Verify screen, not yet a standalone shareable receipt
- Phase 5 integration layer (SDK / API for third-party use)

## Health metrics

| Metric | Value | Target | Source |
|---|---|---|---|
| Contracts test count | 268 across 9 files | n/a | `npm test` in `codes/contracts/` |
| Relayer test count | 96 (2 skipped) | n/a | `npm test` in `codes/relayer/` |
| Client static analysis | clean | clean | `flutter analyze` in `codes/mobile/` |
| `npm run deploy:local` reproducible | yes | yes | deterministic Hardhat addresses |
| CI status | 3 jobs (contracts / relayer / mobile) | green on every PR | `.github/workflows/ci.yml` |
| Open P0 items | 0 | 0 | `improvements/findings.md` |
| Open P1 items | 8 | 0 before any deploy | `improvements/findings.md` |

## How to update this file

- Move items between sections as work progresses.
- Add a dated entry at the top of "In flight" when work starts (`YYYY-MM-DD - what + who`).
- When something ships, **delete the in-flight entry** and update "Shipped". Don't accumulate a history here — that's CHANGELOG's job.
